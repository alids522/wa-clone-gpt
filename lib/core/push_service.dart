import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'controller.dart';
import 'models.dart';
import 'vault.dart';

@pragma('vm:entry-point')
Future<void> backgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
  const vault = DeviceVault();
  if (await vault.read('auth_session') == null) return;
  ChatController? controller;
  StreamSubscription<ChatMessage>? subscription;
  var initialized = false;
  try {
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(vault),
      ),
    );
    initialized = true;
    controller = ChatController(
      vault: vault,
      client: Supabase.instance.client,
      background: true,
    );
    final shown = <Future<void>>[];
    subscription = controller.events.stream.listen((item) {
      shown.add(
        PushService.showMessage(controller!, item).catchError((Object _) {}),
      );
    });
    // Commit decrypted inbox + ratchet before a real encrypted delivered receipt.
    // A background handler never marks messages as read.
    await controller.initialize(syncOnOpen: false);
    if (message.data['kind'] == 'call' && controller.me != null) {
      await PushService.showIncoming(controller, message.data['event_id']!);
    }
    await controller.sync();
    await Future.wait(shown);
  } catch (_) {
    // Failed decryption/auth/network must never fabricate a delivered receipt.
  } finally {
    await subscription?.cancel();
    controller?.dispose();
    if (initialized) await Supabase.instance.client.dispose();
  }
}

enum PushState {
  idle,
  checking,
  ready,
  permissionNeeded,
  setupFailed,
  tokenFailed,
  registrationFailed,
}

class PushService {
  static const configured = bool.fromEnvironment('FIREBASE_ENABLED');
  static final allowed = ValueNotifier<bool>(false);
  static final status = ValueNotifier<PushState>(PushState.idle);
  static String diagnosticCode = '';
  static Future<void>? _initializing;
  static Future<bool>? _enabling;
  static Timer? _retry;
  static String get explanation => switch (status.value) {
    PushState.checking => 'Menyiapkan notifikasi…',
    PushState.ready => 'Notifikasi pesan dan panggilan aktif',
    PushState.permissionNeeded => 'Izinkan notifikasi di pengaturan Android.',
    PushState.setupFailed =>
      'Komponen notifikasi belum siap. Coba lagi atau perbarui aplikasi.',
    PushState.tokenFailed =>
      'Belum terhubung ke Firebase. Periksa koneksi dan Google Play Services lalu coba lagi.',
    PushState.registrationFailed =>
      'Izin notifikasi aktif. Pendaftaran perangkat ke server belum selesai; coba lagi.',
    _ => 'Aktifkan notifikasi pesan dan panggilan.',
  };
  static final notifications = FlutterLocalNotificationsPlugin();
  static final navigation = StreamController<String>.broadcast();
  static String? pendingChat;
  static bool _initialized = false;
  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _foreground;
  static StreamSubscription<ChatMessage>? _events;
  static Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  static Future<void> _initialize() async {
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        pendingChat = response.payload;
        if (pendingChat != null) navigation.add(pendingChat!);
      },
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'adoetz_messages_v2',
            'Pesan',
            description: 'Pesan pribadi Adoetz Chat',
            importance: Importance.high,
          ),
        );
    final launch = await notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      pendingChat = launch!.notificationResponse?.payload;
    }
    _initialized = true;
  }

  static Future<void> restore(ChatController controller) async {
    if (!configured || controller.preview || controller.background) return;
    await enable(controller, requestPermission: false);
  }

  static Future<bool> enable(
    ChatController controller, {
    bool requestPermission = true,
  }) {
    return _enabling ??= _enable(
      controller,
      requestPermission: requestPermission,
    ).whenComplete(() => _enabling = null);
  }

  static Future<bool> _enable(
    ChatController controller, {
    required bool requestPermission,
  }) async {
    if (!configured ||
        controller.preview ||
        controller.me == null ||
        controller.deviceId == null) {
      return false;
    }
    final owner = controller.me!.id, device = controller.deviceId!;
    bool current() =>
        controller.me?.id == owner &&
        controller.deviceId == device &&
        !controller.preview;
    _retry?.cancel();
    status.value = PushState.checking;
    allowed.value = false;
    diagnosticCode = '';
    var failure = PushState.setupFailed;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await initialize();
      final messaging = FirebaseMessaging.instance;
      final permissions = requestPermission
          ? await messaging.requestPermission()
          : await messaging.getNotificationSettings();
      var permitted =
          permissions.authorizationStatus == AuthorizationStatus.authorized ||
          permissions.authorizationStatus == AuthorizationStatus.provisional;
      final channels = await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.getNotificationChannels();
      if (channels?.any(
            (channel) =>
                channel.id == 'adoetz_messages_v2' &&
                channel.importance == Importance.none,
          ) ??
          false) {
        permitted = false;
      }
      Future<void> save(String token) async {
        if (!current()) return;
        await controller.client!
            .rpc(
              'device_settings',
              params: {
                'device': device,
                'operation': 'push',
                'push_token': token,
              },
            )
            .timeout(const Duration(seconds: 15));
      }

      await _refresh?.cancel();
      await _foreground?.cancel();
      await _events?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen((_) {
        if (current()) controller.sync();
      });
      _events = controller.events.stream.listen((item) {
        if (current()) showMessage(controller, item).catchError((Object _) {});
      });
      _refresh = messaging.onTokenRefresh.listen((token) async {
        try {
          await save(token);
          if (current()) {
            allowed.value = permitted;
            status.value = permitted
                ? PushState.ready
                : PushState.permissionNeeded;
          }
        } catch (_) {
          if (current()) {
            status.value = PushState.registrationFailed;
            allowed.value = false;
          }
        }
      });
      failure = PushState.tokenFailed;
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 20),
      );
      if (token == null || token.isEmpty) throw StateError('Token unavailable');
      failure = PushState.registrationFailed;
      await save(token);
      if (!current()) return false;
      allowed.value = permitted;
      status.value = permitted ? PushState.ready : PushState.permissionNeeded;
      return permitted;
    } catch (e) {
      if (!current()) return false;
      status.value = failure;
      diagnosticCode = e is FirebaseException
          ? e.code
          : e is PlatformException
          ? e.code
          : 'unavailable';
      _retry = Timer(const Duration(seconds: 30), () {
        if (current()) restore(controller).catchError((Object _) {});
      });
      return false;
    }
  }

  static Future<void> testNotification() async {
    await initialize();
    await notifications.show(
      id: 5294001,
      title: 'Adoetz Chat',
      body: 'Notifikasi perangkat berfungsi.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'adoetz_messages_v2',
          'Pesan',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static Future<void> showMessage(ChatController c, ChatMessage item) async {
    if (!item.visible ||
        item.senderId == c.me?.id ||
        c.readingChat == item.chatId) {
      return;
    }
    final chat = c.chats.where((chat) => chat.id == item.chatId).firstOrNull;
    if (chat == null || chat.muted || c.blocked.contains(item.senderId)) return;
    await initialize();
    final id =
        int.parse(
          (item.serverId ?? item.id).replaceAll('-', '').substring(0, 8),
          radix: 16,
        ) &
        0x7fffffff;
    await notifications.show(
      id: id,
      title: 'Adoetz Chat',
      body: 'Pesan baru',
      payload: item.chatId,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'adoetz_messages_v2',
          'Pesan',
          channelDescription: 'Pesan pribadi Adoetz Chat',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          category: AndroidNotificationCategory.message,
        ),
      ),
    );
  }

  static Future<void> showIncoming(ChatController c, String id) async {
    final row = await c.client!.rpc(
      'call_action',
      params: {'call_id': id, 'device': c.deviceId, 'operation': 'get'},
    );
    if (row['status'] != 'ringing' ||
        row['caller_id'] == c.me?.id ||
        DateTime.parse(row['expires_at']).isBefore(DateTime.now())) {
      return;
    }
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: id,
        nameCaller: 'Adoetz Chat',
        appName: 'Adoetz Chat',
        handle: 'Panggilan masuk',
        type: row['video'] == true ? 1 : 0,
        duration: DateTime.parse(
          row['expires_at'],
        ).difference(DateTime.now()).inMilliseconds,
        extra: {'chat': row['conversation_id']},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowFullLockedScreen: true,
          backgroundColor: '#080D18',
          actionColor: '#2563EB',
          textAccept: 'Terima',
          textDecline: 'Tolak',
          incomingCallNotificationChannelName: 'Panggilan masuk',
        ),
      ),
    );
  }

  static Future<void> stop({ChatController? controller}) async {
    _retry?.cancel();
    allowed.value = false;
    status.value = PushState.idle;
    await _refresh?.cancel();
    await _foreground?.cancel();
    await _events?.cancel();
    _refresh = null;
    _foreground = null;
    _events = null;
    if (controller?.deviceId != null &&
        controller?.client != null &&
        !controller!.preview) {
      try {
        await controller.client!.rpc(
          'device_settings',
          params: {'device': controller.deviceId, 'operation': 'push'},
        );
      } catch (_) {}
      await notifications.cancelAll();
    }
  }
}
