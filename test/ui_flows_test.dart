import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adoetz_chat/app/app.dart';
import 'package:adoetz_chat/app/theme.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/vault.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/features/call_screen.dart';
import 'package:adoetz_chat/features/chat_screen.dart';
import 'package:adoetz_chat/features/media_widgets.dart';

const previewKey = Key('ui-capture');
Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(previewKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await Directory('build/ui-preview').create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final font in <(String, String)>[
      ('sans-serif', 'C:/Windows/Fonts/segoeui.ttf'),
      (
        'MaterialIcons',
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final file = File(font.$2);
      if (await file.exists()) {
        final loader = FontLoader(font.$1)
          ..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  testWidgets(
    'root Back returns tabs, expires the confirmation and leaves chat routes normally',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var backgrounded = 0;
      const native = MethodChannel('adoetz/device_runtime');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
        call,
      ) async {
        if (call.method == 'background') backgrounded++;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          native,
          null,
        ),
      );
      final c = ChatController(vault: MemoryVault())..openPreview();
      await tester.pumpWidget(AdoetzApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pengaturan').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Maya Putri'), findsOneWidget);
      expect(backgrounded, 0);
      await tester.tap(find.text('Maya Putri'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(backgrounded, 0);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Tekan sekali lagi untuk keluar'), findsOneWidget);
      expect(backgrounded, 0);
      await tester.pump(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounded, 0);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounded, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final mode in [
    'voice',
    'voice-normal',
    'incoming',
    'video',
    'landscape',
  ]) {
    testWidgets(
      'call $mode has usable controls at small widths and large text',
      (tester) async {
        tester.view.physicalSize = mode == 'landscape'
            ? const Size(740, 360)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var muted = 0, accepted = 0, ended = 0;
        final video = mode == 'video' || mode == 'landscape';
        await tester.pumpWidget(
          RepaintBoundary(
            key: previewKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: adoetzTheme(Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(mode == 'voice' ? 2 : 1),
                ),
                child: child!,
              ),
              home: CallView(
                peer: const Person(
                  id: 'peer',
                  username: 'maya_putri',
                  name: 'Maya Putri',
                ),
                state: mode == 'incoming' ? 'ringing' : 'connected',
                video: video,
                incoming: mode == 'incoming',
                active: true,
                elapsed: const Duration(minutes: 2, seconds: 18),
                remote: video
                    ? const ColoredBox(
                        color: Color(0xFF21394D),
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 140,
                            color: Colors.white24,
                          ),
                        ),
                      )
                    : null,
                local: video
                    ? const ColoredBox(
                        key: Key('local-preview'),
                        color: Color(0xFF596B86),
                      )
                    : null,
                onBack: () {},
                onMute: () => muted++,
                onSpeaker: () {},
                onCamera: () {},
                onFlip: () {},
                onVoice: () {},
                onAccept: () => accepted++,
                onEnd: () => ended++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (mode == 'incoming') {
          await tester.tap(find.byTooltip('Terima'));
          expect(accepted, 1);
          await tester.tap(find.byTooltip('Tolak'));
          expect(ended, 1);
        } else {
          await tester.tap(find.byTooltip('Bisukan'));
          expect(muted, 1);
          await tester.tap(find.byTooltip('Akhiri'));
          expect(ended, 1);
        }
        if (video) {
          final start = tester.getTopLeft(
            find.byKey(const Key('local-preview')),
          );
          await tester.drag(
            find.byKey(const Key('local-preview')),
            const Offset(-80, 30),
          );
          await tester.pump();
          expect(
            tester.getTopLeft(find.byKey(const Key('local-preview'))).dx,
            lessThan(start.dx),
          );
        }
        await capture(tester, 'call-$mode');
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} image and document messages show different bubbles and explicit save controls',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = ChatController(vault: MemoryVault())..openPreview();
        final chat = c.chats.first;
        c.messages.clear();
        c.messages.addAll([
          ChatMessage(
            id: 'photo',
            chatId: chat.id,
            senderId: chat.peer.id,
            text: 'Foto',
            at: DateTime.now(),
            delivery: Delivery.delivered,
            kind: 'attachment',
            data: {
              'name': 'holiday.png',
              'mime': 'image/png',
              'presentation': 'image',
              'caption': 'Foto dari perjalanan tadi',
              'size': 1024,
              'thumbnail':
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM1sAAAAASUVORK5CYII=',
            },
          ),
          ChatMessage(
            id: 'doc',
            chatId: chat.id,
            senderId: c.me!.id,
            text: 'report.pdf',
            at: DateTime.now(),
            delivery: Delivery.sent,
            kind: 'attachment',
            data: {
              'name': 'report.pdf',
              'mime': 'application/pdf',
              'size': 2048,
            },
          ),
        ]);
        await tester.pumpWidget(
          RepaintBoundary(
            key: previewKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: adoetzTheme(brightness),
              home: ChatScreen(controller: c, chat: chat),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Foto dari perjalanan tadi'), findsOneWidget);
        expect(find.byType(AttachmentPreviewImage), findsOneWidget);
        expect(find.text('report.pdf'), findsOneWidget);
        expect(find.byTooltip('Simpan ke Galeri'), findsOneWidget);
        expect(find.byTooltip('Simpan ke Download'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'chat-media-${brightness.name}');
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
