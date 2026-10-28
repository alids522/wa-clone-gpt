import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/core/signal_store.dart';
import 'package:adoetz_chat/core/vault.dart';

void main() {
  test(
    'one account on phone and tablet receives independent encrypted copies and genuine background receipts',
    () async {
      const alice = Person(id: 'alice', username: 'alice', name: 'Alice');
      const bob = Person(id: 'bob', username: 'bob', name: 'Bob');
      final stores = {
        for (final id in ['phone', 'tablet', 'bob-device'])
          id: await PersistentSignalStore.create(),
      };
      final directory = {
        for (final entry in stores.entries)
          entry.key: await entry.value.publicBundle(),
      };
      final rows = <Map<String, dynamic>>[];
      SupabaseClient clientFor(String device, String user) => SupabaseClient(
        'https://test.invalid',
        'public-test-key',
        accessToken: () async => 'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final name = request.url.pathSegments.last;
          final args = request.body.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(request.body) ?? {});
          dynamic result;
          switch (name) {
            case 'my_account':
              result = {'role': 'user', 'status': 'active'};
            case 'list_chats':
              result = [];
            case 'chat_devices':
              result = [
                for (final id in stores.keys)
                  {'id': id, 'user_id': id == 'bob-device' ? 'bob' : 'alice'},
              ];
            case 'device_prekey_bundle':
              final bundle = directory[args['device']]!;
              final keys = bundle['prekeys'] as List;
              result = {
                ...bundle,
                if (args['consume'] == true && keys.isNotEmpty)
                  'prekey': keys.removeAt(0),
              };
            case 'sync_device_messages':
              result = rows
                  .where(
                    (r) =>
                        r['sequence'] > args['after_sequence'] &&
                        ((r['ciphertext']['envelopes'] as Map).containsKey(
                              device,
                            ) ||
                            r['ciphertext']['sender_device'] == device),
                  )
                  .toList();
            case 'send_device_message':
              final existing = rows
                  .where(
                    (r) =>
                        r['sender_id'] == user &&
                        r['client_message_id'] == args['client_id'],
                  )
                  .firstOrNull;
              if (existing != null) {
                expect(existing['ciphertext'], args['envelope']);
                result = existing;
              } else {
                result = {
                  'id': 'server-${rows.length + 1}',
                  'sequence': rows.length + 1,
                  'created_at': DateTime.now().toUtc().toIso8601String(),
                  'sender_id': user,
                  'client_message_id': args['client_id'],
                  'ciphertext': args['envelope'],
                };
                rows.add(Map<String, dynamic>.from(result));
              }
            default:
              throw StateError('Unexpected endpoint $name');
          }
          return http.Response(
            jsonEncode(result),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final clients = [
        clientFor('phone', 'alice'),
        clientFor('tablet', 'alice'),
        clientFor('bob-device', 'bob'),
      ];
      final controllers = <ChatController>[];
      final failures = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = stores.keys.elementAt(i);
        final c =
            ChatController(
                vault: MemoryVault(),
                client: clients[i],
                background: i == 2,
                onSyncError: (e, s) => failures.add('$e\n$s'),
              )
              ..me = i == 2 ? bob : alice
              ..deviceId = id
              ..signalStore = stores[id];
        c.chats.add(Conversation(id: 'room', peer: i == 2 ? alice : bob));
        controllers.add(c);
      }
      final phone = controllers[0],
          tablet = controllers[1],
          receiver = controllers[2];
      await phone.send(phone.chats.single, 'Same account, two devices');
      expect(
        phone.messages.single.delivery,
        Delivery.sent,
        reason: failures.join('\n'),
      );
      expect(
        rows.single['ciphertext']['envelopes'].keys,
        unorderedEquals(['tablet', 'bob-device']),
      );
      expect(jsonEncode(rows), isNot(contains('Same account')));
      await receiver.sync();
      expect(receiver.offline, isFalse, reason: failures.join('\n'));
      expect(
        receiver.inChat('room').single.displayText,
        'Same account, two devices',
      );
      expect(receiver.inChat('room').single.delivery, Delivery.delivered);
      await tablet.sync();
      await phone.sync();
      expect(
        tablet.inChat('room').single.displayText,
        'Same account, two devices',
      );
      expect(
        phone.inChat('room').single.delivery,
        Delivery.delivered,
        reason: failures.join('\n'),
      );
      expect(tablet.inChat('room').single.delivery, Delivery.delivered);
      await tablet.send(tablet.chats.single, 'Reply from tablet');
      await receiver.sync();
      await phone.sync();
      expect(
        receiver.inChat('room').map((m) => m.displayText),
        contains('Reply from tablet'),
      );
      expect(
        phone.inChat('room').map((m) => m.displayText),
        contains('Reply from tablet'),
      );
      expect(phone.offline, isFalse);
      expect(tablet.offline, isFalse);
      expect(receiver.offline, isFalse);
      for (final c in controllers) {
        c.dispose();
      }
      for (final c in clients) {
        await c.dispose();
      }
    },
  );

  test(
    'control journal retains tombstones arriving before originals and rejects peer edits',
    () {
      final c = ChatController(vault: MemoryVault())
        ..preview = true
        ..me = const Person(id: 'alice', username: 'alice', name: 'Alice');
      final at = DateTime.utc(2026);
      ChatMessage event(String id, String sender, String op) => ChatMessage(
        id: id,
        chatId: 'room',
        senderId: sender,
        text: 'control',
        at: at,
        kind: 'control',
        data: {'op': op, 'target': 'original', 'text': 'forged'},
      );
      c.messages.add(event('delete', 'bob', 'delete'));
      c.messages.add(
        ChatMessage(
          id: 'original',
          chatId: 'room',
          senderId: 'bob',
          text: 'secret',
          at: at,
        ),
      );
      c.messages.add(event('edit', 'bob', 'edit'));
      expect(c.inChat('room').single.deleted, isTrue);
      expect(c.inChat('room').single.displayText, 'Pesan dihapus');
      c.messages.removeAt(0);
      c.messages.removeLast();
      c.messages.add(event('forged', 'alice', 'edit'));
      expect(c.inChat('room').single.displayText, 'secret');
      c.dispose();
    },
  );
}
