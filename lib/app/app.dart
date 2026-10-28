import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../features/auth_screen.dart';
import '../features/inbox_screen.dart';
import '../features/password_screen.dart';
import 'theme.dart';

class AdoetzApp extends StatelessWidget {
  const AdoetzApp({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      key: ValueKey(controller.me?.id ?? 'signed-out'),
      title: 'Adoetz Chat',
      debugShowCheckedModeBanner: false,
      theme: adoetzTheme(Brightness.light),
      darkTheme: adoetzTheme(Brightness.dark),
      themeMode: controller.theme,
      home: controller.passwordResetRequired
          ? PasswordScreen(controller: controller, forced: true)
          : controller.me == null
          ? AuthScreen(controller: controller)
          : HomeScreen(controller: controller),
    ),
  );
}
