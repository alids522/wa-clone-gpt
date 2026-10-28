// Run manually: flutter test tools/capture_preview_test.dart
// Set ADOETZ_PREVIEW_FONT to Flutter's material_fonts/roboto-regular.ttf.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adoetz_chat/app/app.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/vault.dart';

void main() {
  testWidgets('capture actual Flutter preview screens', (tester) async {
    // This manually invoked widget harness deliberately uses test preferences.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final font = Platform.environment['ADOETZ_PREVIEW_FONT'];
    if (font != null) {
      await tester.runAsync(() async {
        final bytes = await File(font).readAsBytes();
        final loader = FontLoader('sans-serif')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        final icons = await File(
          font.replaceFirst('roboto-regular.ttf', 'materialicons-regular.otf'),
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final c = ChatController(vault: MemoryVault())..theme = ThemeMode.dark;
    c.openPreview();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AdoetzApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/previews').create(recursive: true);
        await File(
          'docs/previews/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        img.dispose();
      });
    }

    await capture('chats-dark');
    await tester.tap(find.text('Maya Putri'));
    await tester.pumpAndSettle();
    await capture('conversation-dark');
    await c.setTheme(ThemeMode.light);
    await tester.pumpAndSettle();
    await capture('conversation-light');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
