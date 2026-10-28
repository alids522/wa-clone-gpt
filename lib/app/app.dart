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
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: controller.locked, child: child!),
          if (controller.locked) _UnlockScreen(controller: controller),
        ],
      ),
      home: controller.passwordResetRequired
          ? PasswordScreen(controller: controller, forced: true)
          : controller.me == null
          ? AuthScreen(controller: controller)
          : HomeScreen(controller: controller),
    ),
  );
}

class _UnlockScreen extends StatefulWidget {
  const _UnlockScreen({required this.controller});
  final ChatController controller;
  @override
  State<_UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<_UnlockScreen> {
  bool busy = false;
  String? error;
  Future<void> unlock() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final accepted = await widget.controller.unlock();
      if (!accepted && mounted) {
        setState(
          () => error =
              'Belum terverifikasi. Coba lagi dengan biometrik atau PIN perangkat.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Verifikasi perangkat belum tersedia. Pastikan kunci layar sudah diatur.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64),
                const SizedBox(height: 24),
                Text(
                  'Adoetz Chat terkunci',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Verifikasi identitas untuk membuka percakapan.',
                  textAlign: TextAlign.center,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(error!, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy ? null : unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(busy ? 'Memverifikasi…' : 'Buka aplikasi'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
