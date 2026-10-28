import 'dart:async';
import 'package:flutter/services.dart';
import 'package:device_runtime/device_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'controller.dart';
import 'models.dart';
import 'vault.dart';

Future<SupabaseClient> _backgroundClient() async {
  const vault = DeviceVault();
  final raw = await vault.read('auth_session');
  if (raw == null) throw StateError('Signed out');
  // Callkit can reuse its headless engine for more than one action.
  try {
    final client = Supabase.instance.client;
    await client.auth.recoverSession(raw);
    return client;
  } catch (_) {}
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(vault),
    ),
  );
  return Supabase.instance.client;
}

@pragma('vm:entry-point')
Future<void> backgroundCallAction(CallEvent event) async {
  String? id, operation;
  if (event is CallEventActionCallDecline) {
    id = event.callKitParams.id;
    operation = 'decline';
  }
  if (event is CallEventActionCallTimeout) {
    id = event.id;
    operation = 'get';
  }
  if (event is CallEventActionCallEnded) {
    id = event.callKitParams.id;
    operation = 'end';
  }
  // Accept launches the authenticated foreground call service; never open media here.
  if (id == null) return;
  try {
    final client = await _backgroundClient();
    final owner = client.auth.currentUser?.id;
    if (owner == null) return;
    final state = await readJson(const DeviceVault(), 'account_$owner');
    if (state['device_id'] == null) return;
    if (operation == 'end') {
      final row = await client
          .rpc(
            'call_action',
            params: {
              'call_id': id,
              'device': state['device_id'],
              'operation': 'get',
            },
          )
          .timeout(const Duration(seconds: 8));
      // Closing a losing device's native popup must not hang up the winner.
      if (row['caller_device'] != state['device_id'] &&
          row['callee_device'] != state['device_id']) {
        return;
      }
    }
    await client
        .rpc(
          'call_action',
          params: {
            'call_id': id,
            'device': state['device_id'],
            'operation': operation,
          },
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {}
}

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
    // Ring/close before account registration, ratchet locking or inbox catch-up.
    // Native FCM normally rings first; this also handles older payloads safely.
    if (message.data['kind'] == 'call' || message.data['kind'] == 'call_end') {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final state = await readJson(vault, 'account_$uid');
      final device = state['device_id'] as String?;
      if (device == null) return;
      final id = message.data['event_id'];
      if (id == null) return;
      final row = Map<String, dynamic>.from(
        await client
            .rpc(
              'call_action',
              params: {'call_id': id, 'device': device, 'operation': 'get'},
            )
            .timeout(const Duration(seconds: 8)),
      );
      if (message.data['kind'] == 'call') {
        if (row['status'] == 'ringing') {
          var name = message.data['caller_name'];
          if (name == null) {
            try {
              final profile = await client
                  .from('profiles')
                  .select('display_name,username')
                  .eq('id', row['caller_id'])
                  .single()
                  .timeout(const Duration(seconds: 3));
              name =
                  profile['display_name'] as String? ??
                  profile['username'] as String?;
            } catch (_) {}
          }
          await PushService.showIncomingRow(row, uid, callerName: name);
        } else if (row['callee_device'] != device ||
            !['connecting', 'connected'].contains(row['status'])) {
          await FlutterCallkitIncoming.endCall(id);
        }
      } else if (row['status'] != 'ringing' &&
          (row['callee_device'] != device ||
              !['connecting', 'connected'].contains(row['status']))) {
        await FlutterCallkitIncoming.endCall(id);
      }
      return;
    }
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
    await controller.sync();
    await Future.wait(shown);
    await controller.backupNow();
  } catch (_) {
    // Failed decryption/auth/network must never fabricate a delivered receipt.
  } finally {
    await subscription?.cancel();
    controller?.dispose();
    // Reset Flutter's singleton too: Firebase reuses this isolate for later
    // pushes, and initialize() otherwise returns a client already disposed.
    if (initialized) await Supabase.instance.dispose();
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
  static final fullScreenAllowed = ValueNotifier<bool>(true);
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
        if (current() && controller.vault is DeviceVault) {
          await DeviceRuntime.configureCallPush(device);
        }
      }

      await _refresh?.cancel();
      await _foreground?.cancel();
      await _events?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen((message) {
        if (!current()) return;
        if (message.data['kind'] == 'call') {
          showIncoming(
            controller,
            message.data['event_id']!,
          ).catchError((Object _) {});
        }
        controller.sync();
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
      await refreshCallPermission();
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

  static Future<void> refreshCallPermission({bool request = false}) async {
    try {
      fullScreenAllowed.value =
          await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (request && !fullScreenAllowed.value) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {
      fullScreenAllowed.value = false;
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
    var name = c.chats
        .where((chat) => chat.id == row['conversation_id'])
        .firstOrNull
        ?.peer
        .name;
    if (name == null) {
      try {
        final profile = await c.client!
            .from('profiles')
            .select('display_name,username')
            .eq('id', row['caller_id'])
            .single()
            .timeout(const Duration(seconds: 3));
        name =
            profile['display_name'] as String? ??
            profile['username'] as String?;
      } catch (_) {}
    }
    await showIncomingRow(
      Map<String, dynamic>.from(row),
      c.me!.id,
      callerName: name,
    );
  }

  static Future<void> showIncomingRow(
    Map<String, dynamic> row,
    String owner, {
    String? callerName,
  }) async {
    if (row['status'] != 'ringing' ||
        row['caller_id'] == owner ||
        DateTime.parse(row['expires_at']).isBefore(DateTime.now())) {
      return;
    }
    final id = row['id'] as String;
    if ((await FlutterCallkitIncoming.activeCalls()).any(
      (call) => call.id == id,
    )) {
      return;
    }
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: id,
        nameCaller: callerName?.trim().isNotEmpty == true
            ? callerName!
            : 'Panggilan masuk',
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
    if (controller?.vault is DeviceVault) {
      await DeviceRuntime.configureCallPush(null);
    }
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
