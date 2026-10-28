import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/media_service.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/core/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a slow thumbnail cannot enqueue the previous account media after logout',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'adoetz-media-owner-',
      );
      final input = await File(
        '${directory.path}/picked.jpg',
      ).writeAsBytes([255, 216, 255, ...List.filled(128, 0)]);
      final previewStarted = Completer<void>(),
          release = Completer<Map<String, dynamic>>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const storage = MethodChannel('plugins.flutter.io/path_provider'),
          native = MethodChannel('adoetz/device_runtime');
      messenger.setMockMethodCallHandler(
        storage,
        (call) async => directory.path,
      );
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'mediaPreview') {
          previewStarted.complete();
          return release.future;
        }
        throw StateError('Unexpected platform call ${call.method}');
      });
      final c = ChatController(vault: MemoryVault())
        ..me = const Person(id: 'alice', username: 'alice', name: 'Alice');
      final chat = Conversation(
        id: 'chat',
        peer: const Person(id: 'peer', username: 'peer', name: 'Peer'),
      );
      try {
        final sending = MediaService.send(c, chat, input, 'picked.jpg');
        final rejected = expectLater(sending, throwsStateError);
        await previewStarted.future.timeout(const Duration(seconds: 5));
        c.me = const Person(
          id: 'other',
          username: 'other',
          name: 'Other account',
        );
        release.complete({});
        await rejected;
        expect(c.messages, isEmpty);
        expect(directory.listSync(), hasLength(1));
        expect(await input.exists(), isTrue);
      } finally {
        messenger.setMockMethodCallHandler(storage, null);
        messenger.setMockMethodCallHandler(native, null);
        c.dispose();
        await input.delete();
        await directory.delete();
      }
    },
  );
}
