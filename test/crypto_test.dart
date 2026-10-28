import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:adoetz_chat/core/signal_store.dart';

Map<String, dynamic> oneTime(Map<String, dynamic> bundle) => {
  ...bundle,
  'prekey': (bundle['prekeys'] as List).first,
};

void main() {
  test(
    'Signal conversation survives serialization and rejects tampered ciphertext',
    () async {
      var alice = await PersistentSignalStore.create();
      var bob = await PersistentSignalStore.create();
      await SignalEngine(
        alice,
      ).establish('bob', oneTime(await bob.publicBundle()));
      final encrypted = await SignalEngine(
        alice,
      ).encrypt('bob', 'A private message 🔐');
      expect(jsonEncode(encrypted), isNot(contains('private message')));
      // Simulate process death after persisting the ratchet + outbox snapshot.
      alice = PersistentSignalStore(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(alice.data))),
      );
      expect(
        await SignalEngine(bob).decrypt('alice', encrypted),
        'A private message 🔐',
      );
      bob = PersistentSignalStore(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(bob.data))),
      );
      final reply = await SignalEngine(bob).encrypt('alice', 'Received');
      expect(await SignalEngine(alice).decrypt('bob', reply), 'Received');
      final next = await SignalEngine(bob).encrypt('alice', 'Tamper target');
      final bytes = base64Decode(next['body']);
      bytes[bytes.length - 1] ^= 1;
      await expectLater(
        SignalEngine(
          alice,
        ).decrypt('bob', {...next, 'body': base64Encode(bytes)}),
        throwsA(anything),
      );
    },
  );
  test('changed identity is rejected after trust on first use', () async {
    final alice = await PersistentSignalStore.create();
    final bob = await PersistentSignalStore.create();
    await SignalEngine(
      alice,
    ).establish('bob', oneTime(await bob.publicBundle()));
    final impostor = await PersistentSignalStore.create();
    await expectLater(
      SignalEngine(
        alice,
      ).establish('bob', oneTime(await impostor.publicBundle())),
      throwsStateError,
    );
  });
}
