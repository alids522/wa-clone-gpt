import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:adoetz_chat/core/history_backup.dart';
import 'package:adoetz_chat/core/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fresh storage restores encrypted history across devices; wrong passwords, tampering and rewrap stay safe',
    () async {
      Map<String, dynamic>? key;
      final archives = <String, Map<String, dynamic>>{};
      final saves = <String, int>{};
      HistoryBackup device(String name) => HistoryBackup(
        owner: 'alice',
        device: name,
        vault: MemoryVault(),
        rpc: (operation, payload) async {
          switch (operation) {
            case 'get':
              return {'key': key, 'archives': archives.values.toList()};
            case 'key':
              key ??= {...payload!, 'revision': 1};
              return {'key': key};
            case 'rekey':
              expect(payload!['key_id'], key!['key_id']);
              expect(payload['revision'], key!['revision']);
              key = {...payload, 'revision': (key!['revision'] as int) + 1};
              return {'key': key};
            case 'save':
              saves[name] = (saves[name] ?? 0) + 1;
              archives[name] = {
                'device_id': name,
                'ciphertext': payload!['ciphertext'],
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              };
              return {'saved_at': DateTime.now().toUtc().toIso8601String()};
            default:
              throw StateError(operation);
          }
        },
      );
      const password = 'login-password-test-1';
      final phone = device('old-phone');
      await phone.open(password: password);
      final originalKeyId = key!['key_id'];
      final snapshot = {
        'messages': [
          {
            'id': 'message-1',
            'text': 'pesan pribadi yang dipulihkan',
            'data': {'key': 'attachment-private-key'},
          },
        ],
        'hidden': [],
        'chats': [],
      };
      await phone.save(snapshot, revision: 10);
      await phone.save(snapshot, revision: 11);
      expect(
        saves['old-phone'],
        1,
        reason: 'Unchanged history must not upload on every sync',
      );
      final server = jsonEncode({'key': key, 'archives': archives});
      expect(server.contains('pesan pribadi'), false);
      expect(server.contains('attachment-private-key'), false);
      expect(server.contains(password), false);

      final fresh = device('reinstalled-phone');
      expect(await fresh.open(), isEmpty);
      expect(fresh.unlocked, false);
      await expectLater(
        fresh.open(password: 'wrong-password'),
        throwsA(anything),
      );
      expect(fresh.unlocked, false);
      expect(key!['key_id'], originalKeyId);
      final restored = await fresh.open(password: password);
      expect(restored.single['messages'], snapshot['messages']);
      await fresh.save(restored.single, revision: 1);
      expect(
        archives.length,
        2,
        reason: 'A new installation must not overwrite the old device archive',
      );

      await fresh.rewrap('new-login-password-2');
      expect(
        key!['key_id'],
        originalKeyId,
        reason:
            'Password changes rewrap the random key, without changing message keys',
      );
      final third = device('third-phone');
      await expectLater(third.open(password: password), throwsA(anything));
      expect((await third.open(password: 'new-login-password-2')).length, 2);

      final original = archives['old-phone']!['ciphertext'];
      final bytes = base64Decode(original);
      bytes[15] ^= 1;
      archives['old-phone']!['ciphertext'] = base64Encode(bytes);
      await expectLater(
        third.open(),
        throwsA(anything),
        reason: 'Authenticated archives must reject corruption',
      );
      archives['old-phone']!['ciphertext'] = original;
      archives['old-phone']!['device_id'] = 'forged-device';
      await expectLater(
        third.open(),
        throwsA(anything),
        reason: 'Archive ciphertext is bound to its owning device',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
