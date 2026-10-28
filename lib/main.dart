import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'core/controller.dart';
import 'core/vault.dart';
import 'core/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (PushService.configured) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(backgroundPush);
      await PushService.initialize();
    } catch (_) {
      PushService.status.value = PushState.setupFailed;
    }
  }
  const vault = DeviceVault();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  SupabaseClient? client;
  String? startupError;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(vault),
        ),
      ).timeout(const Duration(seconds: 8));
      client = Supabase.instance.client;
    } catch (_) {
      startupError =
          'Koneksi belum siap. Periksa jaringan dan buka ulang aplikasi.';
    }
  }
  final controller = ChatController(vault: vault, client: client);
  try {
    await controller.initialize().timeout(const Duration(seconds: 20));
  } catch (_) {
    controller.error = 'Belum dapat membuka akun. Coba masuk kembali.';
  }
  controller.error ??= startupError;
  runApp(AdoetzApp(controller: controller));
}
