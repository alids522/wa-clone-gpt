import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/core/media_service.dart';
import 'package:adoetz_chat/core/vault.dart';

class VerificationProxy extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) => ['127.0.0.1', 'localhost'].contains(uri.host)
            ? 'DIRECT'
            : const String.fromEnvironment(
                'ACCEPTANCE_PROXY',
                defaultValue: 'DIRECT',
              );
}

void main() {
  const fixturePath = String.fromEnvironment('ACCEPTANCE_FIXTURE');
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = VerificationProxy();
  test(
    'live multi-device login, encrypted fanout, receipts, attachments, avatar, access denial and call authorization',
    () async {
      final fixture = jsonDecode(await File(fixturePath).readAsString());
      final users = fixture['users'] as List;
      final clients = <SupabaseClient>[], controllers = <ChatController>[];
      final failures = <String>[];
      final dir = await Directory.systemTemp.createTemp('adoetz-live-test-');
      Future<ChatController> open(int user, {bool background = false}) async {
        final client = SupabaseClient(
          fixture['url'],
          fixture['key'],
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        clients.add(client);
        await client.auth.signInWithPassword(
          email: users[user]['email'],
          password: users[user]['password'],
        );
        final c = ChatController(
          vault: MemoryVault(),
          client: client,
          background: background,
          onSyncError: (e, s) => failures.add('${e.runtimeType}: $e'),
        );
        controllers.add(c);
        await c.initialize();
        expect(
          c.me?.id,
          users[user]['id'],
          reason: c.error ?? failures.join('\n'),
        );
        expect(c.deviceId, isNotNull);
        return c;
      }

      try {
        final phone = await open(0),
            tablet = await open(0),
            bob = await open(1, background: true),
            outsider = await open(2, background: true);
        expect(phone.deviceId, isNot(tablet.deviceId));
        final devices =
            await phone.client!.rpc(
                  'device_settings',
                  params: {'device': phone.deviceId, 'operation': 'list'},
                )
                as List;
        expect(devices.length, 2);
        final room = await phone.startChat(
          Person.fromJson(Map<String, dynamic>.from(users[1])),
        );
        await phone.send(room, 'Live fanout ${const Uuid().v4()}');
        expect(
          phone.messages.first.delivery,
          Delivery.sent,
          reason: failures.join('\n'),
        );
        await bob.sync();
        await tablet.sync();
        await phone.sync();
        expect(
          bob.inChat(room.id).single.delivery,
          Delivery.delivered,
          reason: failures.join('\n'),
        );
        expect(
          tablet.inChat(room.id).single.text,
          phone.inChat(room.id).single.text,
        );
        expect(
          phone.inChat(room.id).single.delivery,
          Delivery.delivered,
          reason: failures.join('\n'),
        );
        expect(
          tablet.inChat(room.id).single.delivery,
          Delivery.delivered,
          reason: failures.join('\n'),
        );
        await tablet.send(tablet.chats.single, 'Sent from the second device');
        await bob.sync();
        await phone.sync();
        expect(bob.inChat(room.id).length, 2, reason: failures.join('\n'));
        expect(phone.inChat(room.id).length, 2);
        final object = '${room.id}/${phone.me!.id}/${const Uuid().v4()}';
        final source = File('${dir.path}/plain');
        await source.writeAsString('Encrypted live attachment');
        final cipher = File('${dir.path}/cipher');
        final metadata = await MediaCipher.encrypt(source, cipher, object)
          ..addAll({
            'name': 'fixture.txt',
            'mime': 'text/plain',
            '_upload_path': cipher.path,
          });
        await phone.send(
          room,
          'fixture.txt',
          kind: 'attachment',
          data: metadata,
        );
        for (
          var i = 0;
          i < 60 &&
              phone.messages
                      .where((m) => m.kind == 'attachment')
                      .single
                      .delivery !=
                  Delivery.sent;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await phone.sync();
        }
        expect(
          phone.messages.where((m) => m.kind == 'attachment').single.delivery,
          Delivery.sent,
          reason: failures.join('\n'),
        );
        await bob.sync();
        final received = bob
            .inChat(room.id)
            .firstWhere((m) => m.kind == 'attachment');
        expect(received.data.containsKey('_upload_path'), isFalse);
        final encryptedBytes = await bob.client!.storage
            .from('chat-media')
            .download(object);
        final downloaded = File('${dir.path}/downloaded');
        await downloaded.writeAsBytes(encryptedBytes);
        final plaintext = File('${dir.path}/decrypted');
        await MediaCipher.decrypt(downloaded, plaintext, received.data);
        expect(await plaintext.readAsString(), 'Encrypted live attachment');
        await expectLater(
          outsider.client!.storage.from('chat-media').download(object),
          throwsA(isA<StorageException>()),
        );
        await expectLater(
          outsider.client!.rpc(
            'sync_device_messages',
            params: {
              'chat': room.id,
              'device': outsider.deviceId,
              'after_sequence': 0,
            },
          ),
          throwsA(isA<PostgrestException>()),
        );
        final avatar = '${phone.me!.id}/${const Uuid().v4()}';
        final pixel = Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1kAAAAASUVORK5CYII=',
          ),
        );
        await phone.client!.storage
            .from('avatars')
            .uploadBinary(
              avatar,
              pixel,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );
        await phone.setAvatar(avatar);
        await bob.sync();
        expect(bob.chats.single.peer.avatarPath, avatar);
        expect(
          await bob.client!.storage.from('avatars').download(avatar),
          pixel,
        );
        final callId = const Uuid().v4();
        await phone.client!.rpc(
          'call_action',
          params: {
            'call_id': callId,
            'device': phone.deviceId,
            'operation': 'start',
            'chat': room.id,
            'is_video': true,
          },
        );
        final turn = await phone.client!.functions.invoke(
          'turn-credentials',
          body: {'call_id': callId, 'device': phone.deviceId},
        );
        expect((turn.data['iceServers'] as List).isNotEmpty, isTrue);
        final accepted = await bob.client!.rpc(
          'call_action',
          params: {
            'call_id': callId,
            'device': bob.deviceId,
            'operation': 'accept',
          },
        );
        expect(accepted['callee_device'], bob.deviceId);
        await expectLater(
          outsider.client!.rpc(
            'call_action',
            params: {
              'call_id': callId,
              'device': outsider.deviceId,
              'operation': 'accept',
            },
          ),
          throwsA(isA<PostgrestException>()),
        );
        await phone.client!.rpc(
          'call_action',
          params: {
            'call_id': callId,
            'device': phone.deviceId,
            'operation': 'end',
          },
        );
        await bob.client!.rpc(
          'submit_report',
          params: {
            'chat': room.id,
            'reason': 'Automated acceptance fixture; no chat content attached',
          },
        );
        expect(failures, isEmpty);
      } finally {
        for (final c in controllers) {
          c.dispose();
        }
        for (final client in clients) {
          await client.dispose();
        }
        for (final file in dir.listSync()) {
          await file.delete();
        }
        await dir.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: fixturePath.isEmpty
        ? 'Requires operator-created disposable live fixtures'
        : false,
  );
}
