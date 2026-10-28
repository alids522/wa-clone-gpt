import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/core/signal_store.dart';
import 'package:adoetz_chat/core/vault.dart';

class FailingVault extends MemoryVault {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Storage unavailable');
}

class PausedSignalStore extends PersistentSignalStore {
  PausedSignalStore(super.data);
  final advanced = Completer<void>(), release = Completer<void>();
  int sessionWrites = 0;
  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    await super.storeSession(address, record);
    if (++sessionWrites == 2) {
      advanced.complete();
      await release.future;
    }
  }
}

void main() {
  const self = Person(id: 'alice', username: 'alice', name: 'Alice');
  const peer = Person(id: 'bob', username: 'bob', name: 'Bob');
  test(
    'upgrade retries a committed legacy envelope without advancing keys',
    () async {
      final vault = MemoryVault();
      final store = await PersistentSignalStore.create();
      final original = jsonEncode(store.data);
      final envelope = <String, dynamic>{
        'protocol': 'signal-v1',
        'body': 'YWJj',
      };
      var sends = 0;
      final client = SupabaseClient(
        'https://staging.example.test',
        'public-test-key',
        accessToken: () async => 'test-token',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final name = request.url.pathSegments.last;
          Object data;
          if (name == 'my_account') {
            data = {'role': 'user', 'status': 'active'};
          } else if (name == 'list_chats' || name == 'sync_device_messages') {
            data = [];
          } else if (name == 'send_message') {
            final args = jsonDecode(request.body);
            expect(args['client_id'], 'old-message');
            expect(args['envelope'], envelope);
            sends++;
            data = {
              'id': 'server-id',
              'sequence': 1,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            };
          } else {
            throw StateError('Upgrade must not encrypt again: $name');
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final failures = <String>[];
      final c =
          ChatController(
              vault: vault,
              client: client,
              onSyncError: (e, s) => failures.add('$e\n$s'),
            )
            ..me = self
            ..signalStore = store
            ..deviceId = 'alice';
      c.chats.add(Conversation(id: 'chat', peer: peer));
      c.messages.add(
        ChatMessage(
          id: 'old-message',
          chatId: 'chat',
          senderId: 'alice',
          text: 'Old queue',
          at: DateTime.now(),
          envelope: envelope,
        ),
      );
      await c.persist();
      await c.sync();
      expect(sends, 1, reason: failures.join('\n'));
      expect(c.messages.single.delivery, Delivery.sent);
      expect(jsonEncode(c.signalStore!.data), original);
      c.dispose();
      await client.dispose();
    },
  );
  test(
    'a concurrent preference write cannot commit a ratchet without its ciphertext',
    () async {
      final vault = MemoryVault();
      final alice = PausedSignalStore(
        (await PersistentSignalStore.create()).data,
      );
      final bob = await PersistentSignalStore.create();
      final bundle = await bob.publicBundle();
      final endpoints = <String>[];
      final transport = MockClient((request) async {
        final name = request.url.pathSegments.last;
        endpoints.add(name);
        final data = switch (name) {
          'my_account' => {'role': 'user', 'status': 'active'},
          'list_chats' || 'sync_messages' => [],
          'get_prekey_bundle' => {
            ...bundle,
            'prekey': (bundle['prekeys'] as List).first,
          },
          'send_message' => {
            'id': 'server-id',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          _ => throw StateError('Unexpected endpoint $name'),
        };
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final client = SupabaseClient(
        'https://staging.example.test',
        'public-test-key',
        httpClient: transport,
        accessToken: () async => 'test-token',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final c = ChatController(vault: vault, client: client)
        ..me = self
        ..signalStore = alice;
      final chat = Conversation(id: 'chat', peer: peer);
      c.chats.add(chat);
      final sending = c.send(chat, 'Atomic message');
      final paused = await Future.any([
        alice.advanced.future.then((_) => true),
        sending.then((_) => false),
      ]).timeout(const Duration(seconds: 5));
      expect(
        paused,
        isTrue,
        reason:
            'Expected paused encryption; endpoints=$endpoints writes=${alice.sessionWrites} error=${c.error} offline=${c.offline}',
      );
      final savingPreference = c.persist();
      var joined = false;
      final joiningSync = c.sync().then((_) => joined = true);
      // Allow the competing write to attempt execution while encrypt() is paused.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        joined,
        isFalse,
        reason: 'Concurrent sync must wait for the active transaction',
      );
      final intermediate = await readJson(vault, 'account_alice');
      expect(intermediate['messages'][0]['envelope'], isNull);
      expect(intermediate['crypto']['sessions'] ?? {}, isEmpty);
      alice.release.complete();
      await sending;
      await savingPreference;
      await joiningSync;
      final committed = await readJson(vault, 'account_alice');
      final envelope = Map<String, dynamic>.from(
        committed['messages'][0]['envelope'],
      );
      final plain = jsonDecode(
        await SignalEngine(bob).decrypt('alice', envelope),
      );
      expect(plain['text'], 'Atomic message');
      expect(committed['crypto']['sessions'], isNotEmpty);
      expect(c.messages.single.delivery, Delivery.sent);
      c.dispose();
      await client.dispose();
    },
  );
  test('offline send commits a durable queue without claiming sent', () async {
    final vault = MemoryVault();
    final c = ChatController(vault: vault)..me = self;
    c.signalStore = await PersistentSignalStore.create();
    final chat = Conversation(id: 'chat', peer: peer);
    c.chats.add(chat);
    await c.send(chat, 'Keep this after a process restart');
    final stored = await readJson(vault, 'account_alice');
    expect(stored['messages'], hasLength(1));
    final recovered = ChatMessage.fromJson(
      Map<String, dynamic>.from(stored['messages'][0]),
    );
    expect(recovered.id, c.messages.single.id);
    expect(recovered.delivery, Delivery.queued);
    expect(stored['crypto']['identity'], c.signalStore!.data['identity']);
    expect(c.offline, isTrue);
    c.dispose();
  });
  test(
    'storage failure does not leave an optimistic message marked as saved',
    () async {
      final c = ChatController(vault: FailingVault())..me = self;
      final chat = Conversation(id: 'chat', peer: peer);
      c.chats.add(chat);
      await expectLater(c.send(chat, 'Do not lose this'), throwsStateError);
      expect(c.messages, isEmpty);
      c.dispose();
    },
  );
}
