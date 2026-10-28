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

void main() {
  const self = Person(id: 'alice', username: 'alice', name: 'Alice');
  const peer = Person(id: 'bob', username: 'bob', name: 'Bob');
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
