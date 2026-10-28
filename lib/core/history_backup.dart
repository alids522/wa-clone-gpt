import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'vault.dart';

typedef BackupRpc =
    Future<Map<String, dynamic>> Function(
      String operation,
      Map<String, dynamic>? payload,
    );

// Run the expensive password KDF off the UI isolate. Passwords are never saved.
Future<List<int>> _passwordKey(Map<String, dynamic> args) async =>
    (await Pbkdf2.hmacSha256(
          iterations: 600000,
          bits: 256,
        ).deriveKeyFromPassword(
          password: args['password'],
          nonce: base64Decode(args['salt']),
        ))
        .extractBytes();

class HistoryBackup {
  HistoryBackup({
    required this.owner,
    required this.device,
    required this.vault,
    required this.rpc,
  });
  final String owner, device;
  final Vault vault;
  final BackupRpc rpc;
  static final _aes = AesGcm.with256bits();
  String? keyId;
  SecretKey? _key;
  Map<String, dynamic>? _envelope;
  String? _savedHash;
  DateTime? savedAt;
  bool get unlocked => _key != null;
  String get _slot => 'history_key_$owner';
  List<int> _aad(String label) =>
      utf8.encode('adoetz/history/$label/v1/$owner/$keyId');

  Future<void> loadLocal() async {
    final local = await readJson(vault, _slot);
    if (local['key'] != null) {
      keyId = local['key_id'];
      _key = SecretKey(base64Decode(local['key']));
    }
  }

  Future<SecretKey> _derive(String password, String salt) async => SecretKey(
    await compute(_passwordKey, {'password': password, 'salt': salt}),
  );

  Future<Map<String, dynamic>> _wrap(String password) async {
    final salt = base64Encode(
      _aes.newNonce().followedBy(_aes.newNonce().take(4)).toList(),
    );
    final box = await _aes.encrypt(
      await _key!.extractBytes(),
      secretKey: await _derive(password, salt),
      aad: _aad('key'),
    );
    return {
      'algorithm': 'pbkdf2-sha256-aes256gcm-v1',
      'key_id': keyId,
      'salt': salt,
      'iterations': 600000,
      'wrapped': {
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'ciphertext': base64Encode(box.cipherText),
      },
    };
  }

  Future<void> _unwrap(Map<String, dynamic> envelope, String password) async {
    _key = null;
    if (envelope['algorithm'] != 'pbkdf2-sha256-aes256gcm-v1' ||
        envelope['iterations'] != 600000) {
      throw StateError('Format backup belum didukung.');
    }
    keyId = envelope['key_id'];
    final wrapped = Map<String, dynamic>.from(envelope['wrapped']);
    final bytes = await _aes.decrypt(
      SecretBox(
        base64Decode(wrapped['ciphertext']),
        nonce: base64Decode(wrapped['nonce']),
        mac: Mac(base64Decode(wrapped['mac'])),
      ),
      secretKey: await _derive(password, envelope['salt']),
      aad: _aad('key'),
    );
    if (bytes.length != 32) throw StateError('Kunci backup tidak valid.');
    _key = SecretKey(bytes);
  }

  /// Missing/wrong passwords never replace the existing key or archives.
  Future<List<Map<String, dynamic>>> open({
    String? password,
    Future<void> Function()? beforeCreate,
    bool createIfMissing = true,
  }) async {
    final remote = await rpc('get', null);
    final envelope = remote['key'] == null
        ? null
        : Map<String, dynamic>.from(remote['key']);
    if (envelope == null) {
      _key = null;
      keyId = null;
      if (password == null || !createIfMissing) return [];
      await beforeCreate?.call();
      keyId = const Uuid().v4();
      _key = await _aes.newSecretKey();
      final proposed = await _wrap(password);
      final actual = await rpc('key', proposed);
      _envelope = Map<String, dynamic>.from(actual['key']);
      // Another device may have created the account key concurrently.
      if (_envelope!['key_id'] != keyId) await _unwrap(_envelope!, password);
    } else {
      _envelope = envelope;
      if (password != null) {
        await _unwrap(envelope, password);
      } else if (keyId != envelope['key_id'] || _key == null) {
        _key = null;
        keyId = envelope['key_id'];
        return [];
      }
    }
    await vault.write(
      _slot,
      jsonEncode({
        'key_id': keyId,
        'key': base64Encode(await _key!.extractBytes()),
      }),
    );
    final archives = <Map<String, dynamic>>[];
    for (final raw in remote['archives'] as List? ?? []) {
      final box = SecretBox.fromConcatenation(
        base64Decode(raw['ciphertext']),
        nonceLength: 12,
        macLength: 16,
      );
      final bytes = await _aes.decrypt(
        box,
        secretKey: _key!,
        aad: _aad('archive/${raw['device_id']}'),
      );
      final archive = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(gzip.decode(bytes))),
      );
      if (archive['owner'] != owner || archive['version'] != 1) {
        throw StateError('Arsip tidak valid.');
      }
      archives.add(archive);
      final at = DateTime.parse(raw['updated_at']);
      if (savedAt == null || at.isAfter(savedAt!)) savedAt = at;
    }
    return archives;
  }

  Future<void> save(
    Map<String, dynamic> snapshot, {
    required int revision,
  }) async {
    if (!unlocked) return;
    final encoded = utf8.encode(
      jsonEncode({...snapshot, 'owner': owner, 'version': 1}),
    );
    final hash = base64Encode((await Sha256().hash(encoded)).bytes);
    if (hash == _savedHash) return;
    final box = await _aes.encrypt(
      gzip.encode(encoded),
      secretKey: _key!,
      aad: _aad('archive/$device'),
    );
    final ciphertext = base64Encode(box.concatenation());
    if (ciphertext.length > 16000000) {
      throw StateError('Backup melebihi batas 12 MB terkompresi.');
    }
    final result = await rpc('save', {
      'key_id': keyId,
      'ciphertext': ciphertext,
      'source_revision': revision,
    });
    savedAt = DateTime.parse(result['saved_at']);
    _savedHash = hash;
  }

  Future<void> rewrap(String password) async {
    if (!unlocked || _envelope == null) {
      throw StateError('Buka backup dengan password sebelumnya dulu.');
    }
    final next = await _wrap(password);
    next['revision'] = _envelope!['revision'];
    final result = await rpc('rekey', next);
    _envelope = Map<String, dynamic>.from(result['key']);
  }
}
