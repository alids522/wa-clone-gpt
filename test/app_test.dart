import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adoetz_chat/app/app.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/core/vault.dart';

void main() {
  test('username and passphrase validation enforces product rules', () {
    expect(validateUsername('maya_123'), isNull);
    for (final name in ['admin', 'system', 'ab', 'Maya', 'user name']) {
      expect(validateUsername(name), isNotNull);
    }
    expect(validatePassword('long passphrase!'), isNull);
    expect(validatePassword('short'), isNotNull);
  });
  testWidgets(
    'preview navigation, draft and queued send are honest and usable',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = ChatController(vault: MemoryVault());
      await tester.pumpWidget(AdoetzApp(controller: c));
      await tester.scrollUntilVisible(
        find.text('Jelajahi pratinjau aplikasi →'),
        220,
      );
      await tester.tap(find.text('Jelajahi pratinjau aplikasi →'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pratinjau lokal · pesan tidak dikirim'),
        findsOneWidget,
      );
      await tester.tap(find.text('Maya Putri'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A local-only draft');
      await tester.tap(find.byTooltip('Kirim pesan'));
      await tester.pumpAndSettle();
      expect(find.text('A local-only draft'), findsOneWidget);
      expect(c.messages.last.delivery, Delivery.queued);
      expect(c.messages.last.envelope, isNull);
      c.dispose();
    },
  );
  testWidgets('welcome and form fit a small screen with 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = ChatController(vault: MemoryVault());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AdoetzApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.openPreview();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Maya Putri'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}
