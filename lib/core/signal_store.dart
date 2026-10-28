import 'dart:convert';
import 'dart:typed_data';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Serialized together with the outbox in one encrypted vault commit.
/// This prevents advancing the ratchet without retaining the ciphertext to retry.
class PersistentSignalStore implements SignalProtocolStore {
  PersistentSignalStore(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> _map(String key) =>
      data.putIfAbsent(key, () => <String, dynamic>{}) as Map<String, dynamic>;
  String _address(SignalProtocolAddress a) =>
      '${a.getName()}:${a.getDeviceId()}';
  Uint8List _bytes(String s) => base64Decode(s);

  static Future<PersistentSignalStore> create() async {
    final identity = generateIdentityKeyPair();
    final store = PersistentSignalStore({
      'identity': base64Encode(identity.serialize()),
      'registration': generateRegistrationId(false),
      'next_prekey': 51,
      'signed_id': 1,
      'signed_at': DateTime.now().toUtc().toIso8601String(),
    });
    for (final key in generatePreKeys(1, 50)) {
      await store.storePreKey(key.id, key);
    }
    final signed = generateSignedPreKey(identity, 1);
    await store.storeSignedPreKey(1, signed);
    return store;
  }

  Future<Map<String, dynamic>> publicBundle() async {
    final signedId = data['signed_id'] as int? ?? 1;
    final signed = await loadSignedPreKey(signedId);
    return {
      'identity_key': base64Encode(
        (await getIdentityKeyPair()).getPublicKey().serialize(),
      ),
      'registration_id': await getLocalRegistrationId(),
      'signed_prekey_id': signedId,
      'signed_prekey': base64Encode(signed.getKeyPair().publicKey.serialize()),
      'signature': base64Encode(signed.signature),
      'prekeys': [
        for (final entry in _map('prekeys').entries)
          {
            'id': int.parse(entry.key),
            'key': base64Encode(
              PreKeyRecord.fromBuffer(
                _bytes(entry.value),
              ).getKeyPair().publicKey.serialize(),
            ),
          },
      ],
    };
  }

  Future<void> replenish() async {
    final keys = _map('prekeys');
    if (keys.length < 20) {
      final next = data['next_prekey'] as int? ?? 51;
      final count = 50 - keys.length;
      for (final key in generatePreKeys(next, count)) {
        await storePreKey(key.id, key);
      }
      data['next_prekey'] = next + count;
    }
    final stamp = DateTime.tryParse(data['signed_at'] ?? '');
    if (stamp == null) {
      data['signed_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (DateTime.now().difference(stamp).inDays >= 7) {
      final next = (data['signed_id'] as int? ?? 1) + 1;
      await storeSignedPreKey(
        next,
        generateSignedPreKey(await getIdentityKeyPair(), next),
      );
      data['signed_id'] = next;
      data['signed_at'] = DateTime.now().toUtc().toIso8601String();
    }
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async =>
      IdentityKeyPair.fromSerialized(_bytes(data['identity']));
  @override
  Future<int> getLocalRegistrationId() async => data['registration'];
  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final s = _map('identities')[_address(address)];
    return s == null ? null : IdentityKey.fromBytes(_bytes(s), 0);
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    final old = await getIdentity(address);
    return old == null ||
        (identityKey != null &&
            base64Encode(old.serialize()) ==
                base64Encode(identityKey.serialize()));
  }

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    final changed = !await isTrustedIdentity(
      address,
      identityKey,
      Direction.sending,
    );
    if (changed) {
      throw StateError(
        'Identitas keamanan kontak berubah. Pengiriman ditahan.',
      );
    }
    _map('identities')[_address(address)] = base64Encode(
      identityKey.serialize(),
    );
    return false;
  }

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final v = _map('prekeys')['$preKeyId'];
    if (v == null) throw InvalidKeyIdException('Prekey unavailable');
    return PreKeyRecord.fromBuffer(_bytes(v));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    _map('prekeys')['$preKeyId'] = base64Encode(record.serialize());
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      _map('prekeys').containsKey('$preKeyId');
  @override
  Future<void> removePreKey(int preKeyId) async {
    _map('prekeys').remove('$preKeyId');
  }

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final v = _map('signed')['$signedPreKeyId'];
    if (v == null) throw InvalidKeyIdException('Signed prekey unavailable');
    return SignedPreKeyRecord.fromSerialized(_bytes(v));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async => [
    for (final v in _map('signed').values)
      SignedPreKeyRecord.fromSerialized(_bytes(v)),
  ];
  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    _map('signed')['$signedPreKeyId'] = base64Encode(record.serialize());
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      _map('signed').containsKey('$signedPreKeyId');
  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    _map('signed').remove('$signedPreKeyId');
  }

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final v = _map('sessions')[_address(address)];
    return v == null
        ? SessionRecord()
        : SessionRecord.fromSerialized(_bytes(v));
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    _map('sessions')[_address(address)] = base64Encode(record.serialize());
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      _map('sessions').containsKey(_address(address));
  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    _map('sessions').remove(_address(address));
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    _map('sessions').removeWhere((key, value) => key.startsWith('$name:'));
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => [
    for (final key in _map('sessions').keys)
      if (key.startsWith('$name:') && !key.endsWith(':1'))
        int.parse(key.split(':').last),
  ];
}

class SignalEngine {
  SignalEngine(this.store);
  final PersistentSignalStore store;
  SessionCipher _cipher(String peer) =>
      SessionCipher(store, store, store, store, SignalProtocolAddress(peer, 1));
  Future<void> establish(String peer, Map<String, dynamic> bundle) async {
    final address = SignalProtocolAddress(peer, 1);
    final identity = IdentityKey.fromBytes(
      base64Decode(bundle['identity_key']),
      0,
    );
    if (!await store.isTrustedIdentity(address, identity, Direction.sending)) {
      throw StateError('Identitas keamanan kontak berubah.');
    }
    if (await store.containsSession(address)) return;
    final key = bundle['prekey'];
    await SessionBuilder(
      store,
      store,
      store,
      store,
      address,
    ).processPreKeyBundle(
      PreKeyBundle(
        bundle['registration_id'],
        1,
        key?['id'],
        key == null ? null : Curve.decodePoint(base64Decode(key['key']), 0),
        bundle['signed_prekey_id'],
        Curve.decodePoint(base64Decode(bundle['signed_prekey']), 0),
        base64Decode(bundle['signature']),
        identity,
      ),
    );
  }

  Future<Map<String, dynamic>> encrypt(String peer, String payload) async {
    final encrypted = await _cipher(
      peer,
    ).encrypt(Uint8List.fromList(utf8.encode(payload)));
    return {
      'protocol': 'signal-v1',
      'type': encrypted.getType(),
      'body': base64Encode(encrypted.serialize()),
    };
  }

  Future<String> decrypt(String peer, Map<String, dynamic> envelope) async {
    if (envelope['protocol'] != 'signal-v1') {
      throw StateError('Unsupported protocol');
    }
    final bytes = base64Decode(envelope['body']);
    final plain = envelope['type'] == CiphertextMessage.prekeyType
        ? await _cipher(peer).decrypt(PreKeySignalMessage(bytes))
        : await _cipher(
            peer,
          ).decryptFromSignal(SignalMessage.fromSerialized(bytes));
    return utf8.decode(plain);
  }
}
