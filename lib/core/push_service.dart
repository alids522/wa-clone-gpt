import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'controller.dart';

@pragma('vm:entry-point')
Future<void> backgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Push contains only opaque IDs. Foreground sync is the source of truth.
}

class PushService {
  static const configured = bool.fromEnvironment('FIREBASE_ENABLED');
  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _foreground;
  static Future<bool> enable(ChatController controller) async {
    if (!configured || controller.preview || controller.me == null) {
      throw StateError('Firebase unavailable');
    }
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(backgroundPush);
    final permissions = await FirebaseMessaging.instance.requestPermission();
    if (permissions.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }
    Future<void> save(String token) async {
      if (controller.me == null || controller.preview) return;
      await controller.client!.rpc(
        'register_push_token',
        params: {'push_token': token},
      );
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await save(token);
    await _refresh?.cancel();
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      save(token).catchError((Object _) {});
    });
    await _foreground?.cancel();
    _foreground = FirebaseMessaging.onMessage.listen((_) {
      controller.sync();
    });
    return true;
  }

  static Future<void> stop() async {
    await _refresh?.cancel();
    await _foreground?.cancel();
    _refresh = null;
    _foreground = null;
  }
}
