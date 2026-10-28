import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:device_runtime/device_runtime.dart';
import 'models.dart';
import 'push_service.dart';
import 'signal_store.dart';
import 'vault.dart';
import 'streaming_storage.dart';
import 'history_backup.dart';

class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  ChatController({
    required this.vault,
    this.client,
    this.background = false,
    this.onSyncError,
    StreamingStorage? uploader,
  }) : _uploader = uploader ?? StreamingStorage();
  final void Function(Object, StackTrace)? onSyncError;
  final bool background;
  final Vault vault;
  final SupabaseClient? client;
  ThemeMode theme = ThemeMode.system;
  Person? me;
  bool passwordResetRequired = false;
  bool protectScreen = false;
  bool appLock = false, locked = false, _authenticating = false;
  bool preview = false, busy = false, offline = false, readReceipts = true;
  String? error;
  final List<Conversation> chats = [];
  final List<ChatMessage> messages = [];
  final Map<String, String> drafts = {};
  final Set<String> blocked = {};
  final Map<String, String> cursors = {};
  PersistentSignalStore? signalStore;
  String? deviceId;
  int _revision = 0;
  final Set<String> hidden = {};
  final Map<String, double> uploadProgress = {};
  String? _uploadingMessage;
  final Map<String, String> _dirtyDrafts = {};
  final StreamController<ChatMessage> events = StreamController.broadcast();
  Timer? _timer;
  Timer? _draftTimer;
  StreamSubscription<AuthState>? _auth;
  RealtimeChannel? _channel;
  Future<void> _serial = Future.value();
  Future<void> _writes = Future.value();
  DateTime _nextRetry = DateTime(2000);
  int _attempt = 0;
  bool _disposed = false, _observing = false;
  Future<void>? _currentSync;
  bool _syncOnOpen = true;
  bool _syncAgain = false, _uploading = false;
  DateTime _uploadRetry = DateTime(2000);
  final StreamingStorage _uploader;
  String? activeChat;
  HistoryBackup? _history;
  Timer? _backupTimer;
  Future<void>? _savingBackup;
  bool backupBusy = false;
  String backupStatus =
      'Masuk kembali untuk mengaktifkan backup dengan password login.';
  bool get backupReady => _history?.unlocked ?? false;
  DateTime? get backupSavedAt => _history?.savedAt;
  bool foreground = true;
  String? get readingChat =>
      foreground && !background && !locked ? activeChat : null;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused && appLock && me != null) {
      locked = true;
      notifyListeners();
    }
    if (foreground) {
      final chat = chats.where((c) => c.id == activeChat).firstOrNull;
      if (chat != null && !locked) {
        markRead(chat);
      } else {
        sync();
      }
    }
  }

  bool get configured => client != null;
  bool get isAdmin => me?.role == 'admin' && me?.status == 'active' && !preview;
  void notifyPreferences() => notifyListeners();
  void setDraft(String chatId, String value) {
    drafts[chatId] = value;
    _dirtyDrafts[chatId] = value;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      persist().catchError((Object _) {
        error = 'Draf belum tersimpan. Periksa penyimpanan perangkat.';
        if (!_disposed) notifyListeners();
      });
    });
  }

  List<ChatMessage> inChat(String id) {
    final visible = {
      for (final m in messages.where(
        (m) => m.chatId == id && m.visible && !hidden.contains(m.id),
      ))
        m.id: ChatMessage.fromJson(m.toJson()),
    };
    final controls =
        messages.where((m) => m.chatId == id && m.kind == 'control').toList()
          ..sort(_messageOrder);
    for (final event in controls) {
      final target = visible[event.data['target']];
      if (target == null) {
        continue; // Tombstones remain in the journal for later sync.
      }
      switch (event.data['op']) {
        case 'delete':
          if (event.senderId == target.senderId) target.deleted = true;
        case 'edit':
          if (event.senderId == target.senderId &&
              !target.deleted &&
              target.kind == 'text') {
            target.editedText = event.data['text'] as String?;
          }
        case 'reaction':
          final emoji = event.data['emoji'] as String? ?? '';
          if (emoji.isEmpty) {
            target.reactions.remove(event.senderId);
          } else {
            target.reactions[event.senderId] = emoji;
          }
      }
    }
    return visible.values.toList()..sort((a, b) {
      if ((a.serverId == null) != (b.serverId == null)) {
        return a.serverId == null ? 1 : -1;
      }
      return _messageOrder(a, b);
    });
  }

  static int _messageOrder(ChatMessage a, ChatMessage b) {
    if (a.sequence != null && b.sequence != null) {
      return a.sequence!.compareTo(b.sequence!);
    }
    final time = a.at.compareTo(b.at);
    return time == 0 ? a.id.compareTo(b.id) : time;
  }

  Future<void> initialize({bool syncOnOpen = true}) async {
    _syncOnOpen = syncOnOpen;
    if (!background) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final prefs = await SharedPreferences.getInstance();
    theme = ThemeMode.values.firstWhere(
      (t) => t.name == prefs.getString('theme'),
      orElse: () => ThemeMode.system,
    );
    if (!background) {
      _auth = client?.auth.onAuthStateChange.listen(
        (event) {
          if (event.event == AuthChangeEvent.signedOut) {
            _clear();
            notifyListeners();
          }
        },
        onError: (_) {
          error = 'Sesi berakhir. Masuk kembali untuk melanjutkan.';
          notifyListeners();
        },
      );
    }
    if (client?.auth.currentSession != null) {
      try {
        await _openAccount();
      } catch (_) {
        _clear();
        error = 'Tidak dapat membuka akun. Coba masuk kembali.';
      }
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    theme = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      'theme',
      value.name,
    );
  }

  Future<void> authenticate({
    required String identifier,
    required String password,
    String? username,
    String? invite,
  }) async {
    if (client == null) throw StateError('Koneksi akun belum dikonfigurasi.');
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (username != null) {
        await client!.auth
            .signUp(
              email: identifier.trim(),
              password: password,
              data: {
                'username': username.trim(),
                'invite_code': invite?.trim(),
              },
            )
            .timeout(const Duration(seconds: 25));
        if (client!.auth.currentSession == null) {
          throw StateError(
            'Akun dibuat. Administrator perlu memeriksa pengaturan konfirmasi email.',
          );
        }
      } else if (identifier.contains('@')) {
        await client!.auth
            .signInWithPassword(email: identifier.trim(), password: password)
            .timeout(const Duration(seconds: 25));
      } else {
        final response = await client!.functions
            .invoke(
              'login-identifier',
              body: {
                'identifier': identifier.trim().toLowerCase(),
                'password': password,
              },
            )
            .timeout(const Duration(seconds: 25));
        await client!.auth.setSession(response.data['refresh_token']);
      }
      await _openAccount();
      if (me != null) {
        try {
          await unlockHistory(password, authenticatedPassword: true);
        } catch (_) {
          // A reset login password must not silently replace an older archive.
          backupStatus =
              'Backup belum terbuka. Gunakan password backup sebelumnya di Pengaturan.';
        }
      }
    } on AuthException {
      error =
          'Username/email atau password tidak sesuai, atau kode undangan tidak dapat digunakan.';
    } on PlatformException catch (e) {
      error = e.code == 'restart_required'
          ? e.message
          : 'Penyimpanan aman belum dapat dibuka. Buka ulang aplikasi.';
    } on TimeoutException {
      error = 'Koneksi terlalu lama. Periksa jaringan lalu coba lagi.';
    } on StateError catch (e) {
      error = e.message.toString();
    } catch (_) {
      error =
          'Belum dapat terhubung. Periksa koneksi atau hubungi administrator.';
    } finally {
      if (error != null) {
        final message = error;
        _clear();
        error = message;
      }
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _prepareAccount() async {
    final uid = client!.auth.currentUser!.id;
    final state = await readJson(vault, 'account_$uid');
    _revision = state['revision'] ?? 0;
    deviceId = state['device_id'] ?? const Uuid().v4();
    hidden
      ..clear()
      ..addAll(List<String>.from(state['hidden'] ?? []));
    Map<String, dynamic> profile;
    Map<String, dynamic> account;
    try {
      profile = await client!
          .from('profiles')
          .select()
          .eq('id', uid)
          .single()
          .timeout(const Duration(seconds: 15));
      account = Map<String, dynamic>.from(
        await client!.rpc('my_account').timeout(const Duration(seconds: 15)),
      );
    } catch (_) {
      if (state['me'] == null || state['crypto'] == null) rethrow;
      profile = Map<String, dynamic>.from(state['me']);
      account = {'role': profile['role'], 'status': profile['status']};
      offline = true;
    }
    if (account['status'] != 'active') {
      if (account['status'] == 'reset_required') {
        passwordResetRequired = true;
        return;
      }
      throw StateError('Akun ini dinonaktifkan. Hubungi administrator.');
    }
    me = Person.fromJson({...profile, ...Map<String, dynamic>.from(account)});
    preview = false;
    chats
      ..clear()
      ..addAll(
        (state['chats'] as List? ?? []).map(
          (j) => Conversation.fromJson(Map<String, dynamic>.from(j)),
        ),
      );
    messages
      ..clear()
      ..addAll(
        (state['messages'] as List? ?? []).map(
          (j) => ChatMessage.fromJson(Map<String, dynamic>.from(j)),
        ),
      );
    drafts
      ..clear()
      ..addAll(Map<String, String>.from(state['drafts'] ?? {}));
    cursors
      ..clear()
      ..addAll(Map<String, String>.from(state['cursors'] ?? {}));
    blocked
      ..clear()
      ..addAll(List<String>.from(state['blocked'] ?? []));
    readReceipts = state['read_receipts'] ?? true;
    protectScreen = state['protect_screen'] ?? false;
    appLock = state['app_lock'] ?? false;
    locked = appLock && !background;
    signalStore = state['crypto'] == null
        ? await PersistentSignalStore.create()
        : PersistentSignalStore(Map<String, dynamic>.from(state['crypto']));
    await signalStore!.replenish();
    await _commit(); // Retain identity before publishing public keys.
    if (!offline) {
      deviceId = await client!
          .rpc(
            'register_device_v2',
            params: {
              'requested_id': deviceId,
              'bundle': await signalStore!.publicBundle(),
              'device_label': 'Android',
            },
          )
          .timeout(const Duration(seconds: 20));
      await _commit();
    }
  }

  Future<void> _openAccount() async {
    await _exclusive(_prepareAccount);
    if (passwordResetRequired || me == null) return;
    final uid = me!.id;
    await _initializeHistory();
    if (background) {
      if (_syncOnOpen) await sync();
      return;
    }
    if (vault is DeviceVault) {
      await DeviceRuntime.protectScreen(protectScreen || appLock);
    }
    _channel = client!
        .channel('inbox-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) {
            sync();
          },
        )
        .subscribe();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (DateTime.now().isAfter(_nextRetry)) sync();
    });
    await sync();
    PushService.restore(this).catchError((Object _) {});
  }

  // UI preference/draft writes must wait for a whole crypto transaction.
  // Otherwise a timer could persist an advanced ratchet before its envelope.
  Future<void> persist() => _exclusive(_commit);

  Future<void> _commit() async {
    if (preview || me == null) return;
    final key = 'account_${me!.id}';
    final writtenDrafts = Map<String, String>.from(drafts);
    final snapshot = jsonEncode({
      'me': me!.toJson(),
      'device_id': deviceId,
      'revision': _revision + 1,
      'hidden': hidden.toList(),
      'chats': chats.map((c) => c.toJson()).toList(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'drafts': writtenDrafts,
      'cursors': cursors,
      'blocked': blocked.toList(),
      'read_receipts': readReceipts,
      'protect_screen': protectScreen,
      'app_lock': appLock,
      'crypto': signalStore?.data,
    });
    final write = _writes.then((_) => vault.write(key, snapshot));
    _writes = write.catchError((Object _) {});
    await write;
    _revision++;
    _dirtyDrafts.removeWhere((key, value) => writtenDrafts[key] == value);
    _backupTimer?.cancel();
    if (!background && backupReady) {
      _backupTimer = Timer(const Duration(seconds: 3), () {
        backupNow().catchError((Object _) {});
      });
    }
  }

  Future<void> _initializeHistory() async {
    final owner = me!.id, device = deviceId!;
    final history = HistoryBackup(
      owner: owner,
      device: device,
      vault: vault,
      rpc: (operation, payload) async {
        if (me?.id != owner ||
            deviceId != device ||
            client?.auth.currentUser?.id != owner) {
          throw StateError('Akun berubah.');
        }
        return Map<String, dynamic>.from(
          await client!
              .rpc(
                'history_backup',
                params: {
                  'device': device,
                  'operation': operation,
                  'payload': payload,
                },
              )
              .timeout(const Duration(seconds: 20)),
        );
      },
    );
    _history = history;
    try {
      await history.loadLocal();
      if (!background) await _mergeHistory(await history.open());
      backupStatus = history.unlocked
          ? 'Backup otomatis aktif.'
          : 'Aktifkan backup dengan password login sebelum hapus data atau reinstall.';
    } catch (_) {
      backupStatus = 'Backup belum dapat disinkronkan. Coba lagi saat online.';
    }
  }

  Future<void> unlockHistory(
    String password, {
    bool authenticatedPassword = false,
    bool createIfMissing = true,
  }) async {
    if (password.isEmpty || preview || _history == null) {
      throw StateError('Masukkan password login.');
    }
    final history = _history!, owner = me!.id;
    backupBusy = true;
    notifyListeners();
    try {
      final archives = await history.open(
        password: password,
        createIfMissing: createIfMissing,
        beforeCreate: authenticatedPassword
            ? null
            : () async {
                final result = await client!.functions.invoke(
                  'login-identifier',
                  body: {
                    'identifier': me!.username,
                    'password': password,
                    'verify_only': true,
                  },
                );
                if (result.data['ok'] != true) {
                  throw StateError('Password login tidak sesuai.');
                }
              },
      );
      if (me?.id != owner || _history != history) return;
      await _mergeHistory(archives);
      await backupNow();
    } catch (_) {
      backupStatus =
          'Backup belum terbuka. Periksa password; jika pernah direset, gunakan password sebelumnya.';
      rethrow;
    } finally {
      backupBusy = false;
      if (!_disposed && me?.id == owner) notifyListeners();
    }
  }

  Future<void> _mergeHistory(List<Map<String, dynamic>> archives) async {
    if (archives.isEmpty) return;
    await _exclusive(() async {
      final known = {for (final m in messages) m.id: m};
      for (final archive in archives) {
        for (final raw in archive['chats'] as List? ?? []) {
          final room = Conversation.fromJson(Map<String, dynamic>.from(raw));
          if (!chats.any((c) => c.id == room.id)) chats.add(room);
        }
        for (final raw in archive['messages'] as List? ?? []) {
          final message = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
          if (![
            'text',
            'attachment',
            'voice',
            'control',
          ].contains(message.kind)) {
            continue;
          }
          final existing = known[message.id];
          if (existing == null) {
            messages.add(message);
            known[message.id] = message;
          } else if ([
                Delivery.sent,
                Delivery.delivered,
                Delivery.read,
              ].contains(message.delivery) &&
              message.delivery.index > existing.delivery.index &&
              existing.delivery != Delivery.failed) {
            existing.delivery = message.delivery;
          }
        }
        hidden.addAll(List<String>.from(archive['hidden'] ?? []));
      }
      await _commit();
    });
    if (!_disposed) notifyListeners();
  }

  Future<void> backupNow() {
    return _savingBackup ??= _saveHistory().whenComplete(
      () => _savingBackup = null,
    );
  }

  Future<void> matchBackupPassword(String password) async {
    if (!backupReady || me == null) {
      throw StateError('Buka backup sebelumnya dulu.');
    }
    final history = _history!, owner = me!.id;
    final verified = await client!.functions.invoke(
      'login-identifier',
      body: {
        'identifier': me!.username,
        'password': password,
        'verify_only': true,
      },
    );
    if (verified.data['ok'] != true || me?.id != owner || _history != history) {
      throw StateError('Password login tidak sesuai.');
    }
    await history.rewrap(password);
    backupStatus = 'Backup otomatis aktif dan memakai password login saat ini.';
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final history = _history;
    if (history == null || !history.unlocked || preview || me == null) return;
    final owner = me!.id;
    Map<String, dynamic>? snapshot;
    var revision = 0;
    await _exclusive(() async {
      if (_history != history || me?.id != owner) return;
      revision = _revision;
      snapshot = {
        'chats': chats.map((c) => c.toJson()).toList(),
        'hidden': hidden.toList()..sort(),
        'messages': messages
            .where(
              (m) =>
                  ['text', 'attachment', 'voice', 'control'].contains(m.kind) &&
                  m.serverId != null &&
                  ![Delivery.queued, Delivery.failed].contains(m.delivery),
            )
            .map(
              (m) => {
                ...m.toJson(),
                'envelope': null,
                'data': {
                  for (final e in m.data.entries)
                    if (!e.key.startsWith('_')) e.key: e.value,
                },
              },
            )
            .toList(),
      };
      // Detach mutable data from subsequent ratchet/inbox transactions.
      snapshot = Map<String, dynamic>.from(jsonDecode(jsonEncode(snapshot)));
    });
    if (snapshot == null) return;
    try {
      await history.save(snapshot!, revision: revision);
      if (_history == history) {
        backupStatus =
            'Backup otomatis aktif. Riwayat tersimpan terenkripsi di server.';
      }
    } catch (_) {
      if (_history == history) {
        backupStatus =
            'Backup belum tersimpan. Riwayat tetap di perangkat; coba lagi saat online.';
      }
      rethrow;
    } finally {
      if (!_disposed && me?.id == owner) notifyListeners();
    }
  }

  Future<void> _exclusive(Future<void> Function() operation) {
    final result = _serial.then((_) async {
      String? token;
      try {
        if (vault is DeviceVault && !preview) {
          token = await DeviceRuntime.acquire();
          if (me != null) {
            final latest = await readJson(vault, 'account_${me!.id}');
            if ((latest['revision'] as int? ?? 0) > _revision) {
              _restoreTransaction(latest);
            }
          }
        }
        await operation();
      } finally {
        if (token != null) await DeviceRuntime.release(token);
      }
    });
    _serial = result.catchError((Object _) {});
    return result;
  }

  void _restoreTransaction(Map<String, dynamic> state) {
    _revision = state['revision'] ?? 0;
    deviceId = state['device_id'];
    signalStore = PersistentSignalStore(
      Map<String, dynamic>.from(state['crypto']),
    );
    messages
      ..clear()
      ..addAll(
        (state['messages'] as List).map(
          (j) => ChatMessage.fromJson(Map<String, dynamic>.from(j)),
        ),
      );
    for (final j in state['chats'] as List) {
      final restored = Conversation.fromJson(Map<String, dynamic>.from(j));
      final existing = chats.where((c) => c.id == restored.id).firstOrNull;
      if (existing == null) {
        chats.add(restored);
      } else {
        existing.peer = restored.peer;
        existing.unread = restored.unread;
        existing.pinned = restored.pinned;
        existing.muted = restored.muted;
      }
    }
    drafts
      ..clear()
      ..addAll(Map<String, String>.from(state['drafts'] ?? {}))
      ..addAll(_dirtyDrafts);
    cursors
      ..clear()
      ..addAll(Map<String, String>.from(state['cursors'] ?? {}));
    blocked
      ..clear()
      ..addAll(List<String>.from(state['blocked'] ?? []));
    hidden
      ..clear()
      ..addAll(List<String>.from(state['hidden'] ?? []));
    readReceipts = state['read_receipts'] ?? true;
    protectScreen = state['protect_screen'] ?? false;
    appLock = state['app_lock'] ?? false;
  }

  Future<void> sync() {
    if (preview || me == null || _disposed) return Future.value();
    if (_currentSync != null) {
      _syncAgain = true;
      return _currentSync!;
    }
    final completed = Completer<void>();
    _currentSync = completed.future;
    unawaited(_runSyncLoop(completed));
    return completed.future;
  }

  Future<void> _runSyncLoop(Completer<void> completed) async {
    try {
      do {
        _syncAgain = false;
        await _syncOnce();
      } while (_syncAgain && !_disposed && me != null && !preview);
    } catch (e, s) {
      completed.completeError(e, s);
    } finally {
      _currentSync = null;
      if (!completed.isCompleted) completed.complete();
    }
  }

  Future<void> _syncOnce() async {
    if (!background && !_uploading && DateTime.now().isAfter(_uploadRetry)) {
      _uploading = true;
      _uploadPending()
          .catchError((Object failure, StackTrace stack) {
            onSyncError?.call(failure, stack);
            _uploadRetry = DateTime.now().add(const Duration(seconds: 30));
          })
          .whenComplete(() => _uploading = false);
    }
    try {
      await _exclusive(() async {
        final current = await client!
            .rpc('my_account')
            .timeout(const Duration(seconds: 15));
        if (current['status'] != 'active') {
          await client!.auth.signOut(scope: SignOutScope.local);
          _clear();
          return;
        }
        me = Person(
          id: me!.id,
          username: me!.username,
          name: me!.name,
          bio: me!.bio,
          avatarPath: me!.avatarPath,
          role: current['role'],
          status: current['status'],
        );
        final rows = await client!.rpc('list_chats');
        for (final row in rows as List) {
          final existing = chats.where((c) => c.id == row['id']).firstOrNull;
          if (existing != null) {
            existing.peer = Person.fromJson(
              Map<String, dynamic>.from(row['peer']),
            );
          } else {
            chats.add(
              Conversation(
                id: row['id'],
                peer: Person.fromJson(Map<String, dynamic>.from(row['peer'])),
              ),
            );
          }
        }
        for (final chat in chats) {
          var more = true;
          while (more) {
            final page = await client!.rpc(
              deviceId == null ? 'sync_messages' : 'sync_device_messages',
              params: {
                'chat': chat.id,
                'after_sequence': int.tryParse(cursors[chat.id] ?? '') ?? 0,
                if (deviceId != null) 'device': deviceId,
              },
            );
            more = (page as List).length == 50;
            for (final row in page) {
              final sequence = row['sequence'].toString();
              final transport = Map<String, dynamic>.from(row['ciphertext']);
              final multi = transport['protocol'] == 'signal-devices-v2';
              final ownDevice = multi
                  ? transport['sender_device'] == deviceId
                  : row['sender_id'] == me!.id;
              if (ownDevice) {
                for (final m in messages.where(
                  (m) => m.id == row['client_message_id'],
                )) {
                  m.serverId = row['id'];
                  m.sequence = row['sequence'];
                  m.at = DateTime.parse(row['created_at']);
                  if (m.delivery == Delivery.queued ||
                      m.delivery == Delivery.failed) {
                    m.delivery = Delivery.sent;
                  }
                }
              } else if (!messages.any((m) => m.serverId == row['id'])) {
                final envelope = multi
                    ? Map<String, dynamic>.from(
                        transport['envelopes'][deviceId],
                      )
                    : transport;
                final before = jsonEncode(signalStore!.data);
                final beforeLength = messages.length;
                final unread = chat.unread;
                final statuses = {for (final m in messages) m.id: m.delivery};
                try {
                  final content = jsonDecode(
                    await SignalEngine(signalStore!).decrypt(
                      multi ? transport['sender_device'] : chat.peer.id,
                      envelope,
                    ),
                  );
                  if (content['chat'] != chat.id ||
                      content['sender'] != row['sender_id'] ||
                      content['id'] != row['client_message_id']) {
                    throw StateError('Invalid message binding');
                  }
                  if (multi &&
                      content['sender_device'] != transport['sender_device']) {
                    throw StateError('Invalid device binding');
                  }
                  messages.add(
                    ChatMessage(
                      id: row['client_message_id'],
                      serverId: row['id'],
                      sequence: row['sequence'],
                      chatId: chat.id,
                      senderId: row['sender_id'],
                      text: content['text'],
                      at: DateTime.parse(row['created_at']),
                      delivery: row['sender_id'] == me!.id
                          ? Delivery.sent
                          : Delivery.delivered,
                      kind: content['kind'] ?? 'text',
                      data: {
                        for (final entry in Map<String, dynamic>.from(
                          content['data'] ?? {},
                        ).entries)
                          if (!entry.key.startsWith('_'))
                            entry.key: entry.value,
                        if (multi) 'origin_device': transport['sender_device'],
                      },
                    ),
                  );
                  if (content['kind'] == 'receipt') {
                    final receipt = jsonDecode(content['text']);
                    if (!['delivered', 'read'].contains(receipt['state']) ||
                        (receipt['ids'] as List).length > 50) {
                      throw StateError('Invalid receipt');
                    }
                    for (final m in messages.where(
                      (m) =>
                          m.chatId == chat.id &&
                          m.senderId == me!.id &&
                          m.visible &&
                          (receipt['ids'] as List).contains(m.id),
                    )) {
                      final next = Delivery.values.byName(receipt['state']);
                      if (next.index > m.delivery.index ||
                          m.delivery == Delivery.failed) {
                        m.delivery = next;
                      }
                    }
                  } else if ([
                    'text',
                    'attachment',
                    'voice',
                  ].contains(content['kind'] ?? 'text')) {
                    if (row['sender_id'] != me!.id) {
                      if (readingChat != chat.id) chat.unread++;
                      _queueReceipt(
                        chat.id,
                        [row['client_message_id'] as String],
                        readingChat == chat.id && readReceipts
                            ? 'read'
                            : 'delivered',
                      );
                      if (readingChat == chat.id && readReceipts) {
                        messages
                                .firstWhere((m) => m.serverId == row['id'])
                                .delivery =
                            Delivery.read;
                      }
                    }
                  } else if (!['control', 'signal'].contains(content['kind'])) {
                    throw StateError('Unsupported event');
                  }
                  await _commit(); // Commit received plaintext + ratchet before advancing cursor or ACK.
                  final received = messages.firstWhere(
                    (m) => m.serverId == row['id'],
                  );
                  events.add(received);
                } catch (_) {
                  messages.removeRange(beforeLength, messages.length);
                  chat.unread = unread;
                  for (final m in messages) {
                    m.delivery = statuses[m.id]!;
                  }
                  signalStore = PersistentSignalStore(
                    Map<String, dynamic>.from(jsonDecode(before)),
                  );
                  error =
                      'Pesan ini belum dapat dibuka dengan aman. Sinkronisasi ditahan.';
                  rethrow;
                }
              }
              cursors[chat.id] = sequence;
              await _commit();
            }
          }
        }
        await _flush();
        await _commit();
      });
      offline = false;
      _attempt = 0;
    } catch (failure, stack) {
      onSyncError?.call(failure, stack);
      offline = true;
      _attempt = min(_attempt + 1, 6);
      _nextRetry = DateTime.now().add(
        Duration(seconds: min(120, 1 << _attempt) + Random.secure().nextInt(4)),
      );
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _uploadPending() async {
    final owner = me?.id;
    var jobs = <Map<String, dynamic>>[];
    await _exclusive(() async {
      jobs = messages
          .where(
            (m) =>
                m.senderId == owner &&
                m.delivery == Delivery.queued &&
                m.data['_upload_path'] != null,
          )
          .map(
            (m) => {
              'id': m.id,
              'path': m.data['_upload_path'],
              'object': m.data['object'],
            },
          )
          .toList();
    });
    for (final job in jobs) {
      if (me?.id != owner || _disposed) return;
      var pending = false;
      await _exclusive(() async {
        pending = messages.any(
          (m) =>
              m.id == job['id'] &&
              m.delivery == Delivery.queued &&
              m.data['_upload_path'] == job['path'],
        );
      });
      if (!pending) continue;
      final file = File(job['path']);
      try {
        _uploadingMessage = job['id'];
        await _uploader.upload(
          client!,
          job['object'],
          file,
          onProgress: (progress) {
            if (me?.id == owner && !_disposed) {
              uploadProgress[job['id']] = progress;
              notifyListeners();
            }
          },
        );
        var committed = false;
        await _exclusive(() async {
          if (me?.id != owner) return;
          final m = messages.where((m) => m.id == job['id']).firstOrNull;
          if (m == null ||
              m.delivery != Delivery.queued ||
              m.data['_upload_path'] != job['path']) {
            return;
          }
          m.data.remove('_upload_path');
          await _commit();
          committed = true;
        });
        if (committed) {
          if (await file.exists()) await file.delete();
          await sync();
        }
      } on StorageException catch (e) {
        if (!['400', '401', '403', '413'].contains(e.statusCode)) rethrow;
        await _exclusive(() async {
          if (me?.id != owner) return;
          final m = messages.where((m) => m.id == job['id']).firstOrNull;
          if (m != null) {
            m.delivery = Delivery.failed;
            await _commit();
          }
        });
      } finally {
        uploadProgress.remove(job['id']);
        _uploadingMessage = null;
        if (!messages.any((m) => m.id == job['id']) && await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> send(
    Conversation chat,
    String text, {
    String kind = 'text',
    Map<String, dynamic>? data,
    VoidCallback? onCommitted,
  }) async {
    final body = text.trim();
    final owner = me?.id;
    if (body.isEmpty || body.length > 10000 || blocked.contains(chat.peer.id)) {
      return;
    }
    await _exclusive(() async {
      if (me?.id != owner) return;
      messages.add(
        ChatMessage(
          id: const Uuid().v4(),
          chatId: chat.id,
          senderId: me!.id,
          text: body,
          kind: kind,
          data: data,
          at: DateTime.now(),
        ),
      );
      if (kind == 'text' && drafts[chat.id]?.trim() == body) {
        drafts.remove(chat.id);
        _dirtyDrafts.remove(chat.id);
      }
      try {
        await _commit();
      } catch (_) {
        messages.removeLast();
        rethrow;
      }
      onCommitted?.call();
      notifyListeners();
    });
    if (!preview) await sync();
  }

  Future<void> _flush() async {
    for (final m in messages.where(
      (m) => m.senderId == me!.id && m.delivery == Delivery.queued,
    )) {
      final chat = chats.firstWhere((c) => c.id == m.chatId);
      if (blocked.contains(chat.peer.id)) {
        m.delivery = Delivery.failed;
        continue;
      }
      try {
        final uploadPath = m.data['_upload_path'] as String?;
        if (uploadPath != null) continue;
        if (deviceId != null) {
          await _sendToDevices(chat, m);
          continue;
        }
        final bundle = Map<String, dynamic>.from(
          await client!.rpc(
            'get_prekey_bundle',
            params: {
              'peer': chat.peer.id,
              'consume': !await signalStore!.containsSession(
                SignalProtocolAddress(chat.peer.id, 1),
              ),
            },
          ),
        );
        final snapshot = jsonEncode(signalStore!.data);
        try {
          await SignalEngine(signalStore!).establish(chat.peer.id, bundle);
          m.envelope ??= await SignalEngine(signalStore!).encrypt(
            chat.peer.id,
            jsonEncode({
              'chat': chat.id,
              'sender': me!.id,
              'id': m.id,
              'text': m.text,
              'kind': m.kind,
            }),
          );
          await _commit(); // Atomic ratchet + envelope. Retry always uses this envelope.
        } catch (_) {
          signalStore = PersistentSignalStore(
            Map<String, dynamic>.from(jsonDecode(snapshot)),
          );
          m.delivery = Delivery.failed;
          m.envelope = null;
          rethrow;
        }
        final result = await client!
            .rpc(
              'send_message',
              params: {
                'chat': chat.id,
                'client_id': m.id,
                'envelope': m.envelope,
              },
            )
            .timeout(const Duration(seconds: 20));
        m.serverId = result['id'];
        m.sequence = result['sequence'];
        m.at = DateTime.parse(result['created_at']);
        m.delivery = Delivery.sent;
        await _commit();
      } on PostgrestException catch (e) {
        if (['42501', '22023', 'P0001'].contains(e.code)) {
          m.delivery = Delivery.failed;
        }
        rethrow;
      }
    }
  }

  Future<void> _sendToDevices(Conversation chat, ChatMessage m) async {
    // Preserve an already committed 0.1.0 envelope and its advanced ratchet.
    // Re-encrypting or changing its idempotency payload could lose the old queue.
    if (m.envelope?['protocol'] == 'signal-v1') {
      final result = await client!
          .rpc(
            'send_message',
            params: {
              'chat': chat.id,
              'client_id': m.id,
              'envelope': m.envelope,
            },
          )
          .timeout(const Duration(seconds: 20));
      m.serverId = result['id'];
      m.sequence = result['sequence'];
      m.at = DateTime.parse(result['created_at']);
      m.delivery = Delivery.sent;
      await _commit();
      return;
    }
    if (m.envelope == null) {
      final devices =
          await client!.rpc('chat_devices', params: {'chat': chat.id}) as List;
      if (!devices.any((d) => d['user_id'] == chat.peer.id)) {
        throw StateError('Kontak belum menyiapkan perangkat.');
      }
      final before = jsonEncode(signalStore!.data);
      try {
        final copies = <String, dynamic>{};
        for (final device in devices) {
          final id = device['id'] as String;
          if (id == deviceId) continue;
          final bundle = Map<String, dynamic>.from(
            await client!.rpc(
              'device_prekey_bundle',
              params: {
                'chat': chat.id,
                'device': id,
                'consume': !await signalStore!.containsSession(
                  SignalProtocolAddress(id, 1),
                ),
              },
            ),
          );
          await SignalEngine(signalStore!).establish(id, bundle);
          copies[id] = await SignalEngine(signalStore!).encrypt(
            id,
            jsonEncode({
              'chat': chat.id,
              'sender': me!.id,
              'sender_device': deviceId,
              'id': m.id,
              'text': m.text,
              'kind': m.kind,
              'data': {
                for (final entry in m.data.entries)
                  if (!entry.key.startsWith('_')) entry.key: entry.value,
              },
            }),
          );
        }
        m.envelope = {
          'protocol': 'signal-devices-v2',
          'sender_device': deviceId,
          'notify': m.visible,
          'objects': ['attachment', 'voice'].contains(m.kind)
              ? [m.data['object']]
              : [],
          'envelopes': copies,
        };
        await _commit();
      } catch (_) {
        signalStore = PersistentSignalStore(
          Map<String, dynamic>.from(jsonDecode(before)),
        );
        m.envelope = null;
        rethrow;
      }
    }
    final result = await client!
        .rpc(
          'send_device_message',
          params: {'chat': chat.id, 'client_id': m.id, 'envelope': m.envelope},
        )
        .timeout(const Duration(seconds: 20));
    m.serverId = result['id'];
    m.sequence = result['sequence'];
    m.at = DateTime.parse(result['created_at']);
    m.delivery = Delivery.sent;
    await _commit();
  }

  Future<void> control(
    Conversation chat,
    ChatMessage message,
    String op, {
    String? value,
  }) async {
    if (['edit', 'delete'].contains(op) && message.senderId != me!.id) {
      throw StateError('Hanya pemilik pesan.');
    }
    if (op == 'edit' &&
        (value == null || value.trim().isEmpty || value.length > 10000)) {
      return;
    }
    await send(
      chat,
      'Perubahan pesan',
      kind: 'control',
      data: {
        'op': op,
        'target': message.id,
        if (op == 'edit') 'text': value,
        if (op == 'reaction') 'emoji': value ?? '',
      },
    );
  }

  Future<void> hideMessage(String id) async {
    await _exclusive(() async {
      hidden.add(id);
      await _commit();
    });
    notifyListeners();
  }

  Future<void> retryMessage(String id) async {
    _uploadRetry = DateTime(2000);
    await _exclusive(() async {
      messages.firstWhere((m) => m.id == id).delivery = Delivery.queued;
      await _commit();
    });
    await sync();
  }

  Future<void> cancelAttachment(String id) async {
    if (_uploadingMessage == id) _uploader.cancel();
    String? path;
    await _exclusive(() async {
      final item = messages
          .where(
            (m) =>
                m.id == id &&
                m.senderId == me?.id &&
                m.envelope == null &&
                m.data['_upload_path'] != null,
          )
          .firstOrNull;
      if (item == null) return;
      path = item.data['_upload_path'];
      hidden.add(id);
      messages.remove(item);
      await _commit();
    });
    if (path != null) {
      try {
        await File(path!).delete();
      } catch (_) {}
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> cancelQueued(String id) async {
    if (messages.any((m) => m.id == id && m.data['_upload_path'] != null)) {
      await cancelAttachment(id);
      return;
    }
    await _exclusive(() async {
      final m = messages.firstWhere((m) => m.id == id);
      if (m.serverId != null || m.delivery != Delivery.queued) return;
      m.delivery = Delivery.failed;
      m.data['_cancelled'] = true;
      final path = m.data.remove('_upload_path') as String?;
      await _commit();
      if (path != null && await File(path).exists()) await File(path).delete();
    });
    notifyListeners();
  }

  void _queueReceipt(String chat, List<String> ids, String state) {
    messages.add(
      ChatMessage(
        id: const Uuid().v4(),
        chatId: chat,
        senderId: me!.id,
        text: jsonEncode({'ids': ids, 'state': state}),
        at: DateTime.now(),
        kind: 'receipt',
      ),
    );
  }

  Future<void> markRead(Conversation chat) async {
    if (preview) {
      chat.unread = 0;
      notifyListeners();
      return;
    }
    await _exclusive(() async {
      chat.unread = 0;
      if (!readReceipts) {
        await _commit();
        return;
      }
      final unread = messages
          .where(
            (m) =>
                m.chatId == chat.id &&
                m.senderId == chat.peer.id &&
                m.visible &&
                m.delivery != Delivery.read,
          )
          .toList();
      for (var start = 0; start < unread.length; start += 50) {
        final chunk = unread.skip(start).take(50).toList();
        _queueReceipt(chat.id, chunk.map((m) => m.id).toList(), 'read');
        for (final m in chunk) {
          m.delivery = Delivery.read;
        }
      }
      await _commit();
    });
    await sync();
  }

  Future<List<Person>> searchPeople(String query) async {
    if (query.trim().length < 3) return [];
    if (preview) {
      return chats
          .map((c) => c.peer)
          .where(
            (p) =>
                p.username.contains(query.toLowerCase()) ||
                p.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
    final result = await client!
        .rpc('search_people', params: {'prefix': query.trim().toLowerCase()})
        .timeout(const Duration(seconds: 15));
    return (result as List)
        .map((r) => Person.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<Conversation> startChat(Person peer) async {
    for (final chat in chats) {
      if (chat.peer.id == peer.id) return chat;
    }
    final id = preview
        ? const Uuid().v4()
        : await client!.rpc('create_chat', params: {'peer': peer.id}) as String;
    final chat = Conversation(id: id, peer: peer);
    chats.add(chat);
    await persist();
    notifyListeners();
    return chat;
  }

  Future<void> updateProfile(String name, String bio) async {
    if (!preview) {
      await client!
          .from('profiles')
          .update({'display_name': name.trim(), 'bio': bio.trim()})
          .eq('id', me!.id);
    }
    me = Person(
      id: me!.id,
      username: me!.username,
      name: name.trim(),
      bio: bio.trim(),
      role: me!.role,
      status: me!.status,
      avatarPath: me!.avatarPath,
    );
    await persist();
    notifyListeners();
  }

  Future<void> block(Person peer) async {
    if (!preview) {
      await client!.from('blocked_users').insert({
        'blocker_id': me!.id,
        'blocked_id': peer.id,
      });
    }
    await _exclusive(() async {
      blocked.add(peer.id);
      await _commit();
    });
    notifyListeners();
  }

  Future<void> unblock(String id) async {
    if (!preview) {
      await client!
          .from('blocked_users')
          .delete()
          .eq('blocker_id', me!.id)
          .eq('blocked_id', id);
    }
    await _exclusive(() async {
      blocked.remove(id);
      await _commit();
    });
    notifyListeners();
  }

  Future<void> setAvatar(String? path) async {
    if (!preview) {
      await client!
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', me!.id);
    }
    me = Person.fromJson({...me!.toJson(), 'avatar_path': path});
    await persist();
    notifyListeners();
  }

  Future<void> setReadReceipts(bool enabled) async {
    await _exclusive(() async {
      readReceipts = enabled;
      await _commit();
    });
    notifyListeners();
  }

  Future<void> setScreenProtection(bool enabled) async {
    await _exclusive(() async {
      protectScreen = enabled;
      await _commit();
    });
    if (vault is DeviceVault && !background) {
      await DeviceRuntime.protectScreen(enabled || appLock);
    }
    notifyListeners();
  }

  Future<bool> unlock() async {
    if (_authenticating || background) return false;
    final owner = me?.id;
    _authenticating = true;
    try {
      final accepted = await DeviceRuntime.authenticate();
      if (!accepted || me?.id != owner || _disposed) return false;
      locked = false;
      notifyListeners();
      final chat = chats.where((c) => c.id == activeChat).firstOrNull;
      if (chat != null && foreground) await markRead(chat);
      return true;
    } finally {
      _authenticating = false;
    }
  }

  Future<bool> setAppLock(bool enabled) async {
    final owner = me?.id;
    if (!await unlock() || me?.id != owner) return false;
    await _exclusive(() async {
      appLock = enabled;
      await _commit();
    });
    if (vault is DeviceVault) {
      await DeviceRuntime.protectScreen(protectScreen || appLock);
    }
    notifyListeners();
    return true;
  }

  Future<void> toggleChatPreference(
    Conversation chat, {
    required bool pin,
  }) async {
    await _exclusive(() async {
      if (pin) {
        chat.pinned = !chat.pinned;
      } else {
        chat.muted = !chat.muted;
      }
      await _commit();
    });
    notifyListeners();
  }

  Future<void> changePassword(
    String password, {
    String? currentPassword,
  }) async {
    if (password.length < 12) throw StateError('Gunakan minimal 12 karakter.');
    // Prepare the old archive key before changing credentials. The same random
    // key is rewrapped, so other devices and all existing archives stay valid.
    if (!passwordResetRequired && currentPassword != null && _history != null) {
      await unlockHistory(currentPassword, createIfMissing: false);
    }
    final result = await client!.functions.invoke(
      'account-password',
      body: {'new_password': password, 'current_password': ?currentPassword},
    );
    if (result.data['ok'] != true) {
      throw StateError('Password belum dapat diganti.');
    }
    if (passwordResetRequired) {
      passwordResetRequired = false;
      await _openAccount();
      notifyListeners();
    }
    if (_history?.unlocked ?? false) {
      try {
        await _history!.rewrap(password);
      } catch (_) {
        backupStatus =
            'Password login berubah. Backup masih memakai password sebelumnya; buka Pengaturan untuk menyamakannya.';
      }
    } else if (_history != null) {
      try {
        await unlockHistory(password, authenticatedPassword: true);
      } catch (_) {}
    }
  }

  Future<void> logout() async {
    _uploader.cancel();
    await _serial;
    await PushService.stop(controller: this);
    if (!preview) {
      await persist();
      try {
        await backupNow();
      } catch (_) {}
      await client?.auth.signOut(scope: SignOutScope.local);
    }
    _clear();
    if (vault is DeviceVault && !background) {
      await DeviceRuntime.protectScreen(false);
    }
    notifyListeners();
  }

  void _clear() {
    if (vault is DeviceVault && !background) {
      DeviceRuntime.configureCallPush(null).catchError((Object _) {});
    }
    _backupTimer?.cancel();
    _history = null;
    backupBusy = false;
    backupStatus =
        'Masuk kembali untuk mengaktifkan backup dengan password login.';
    _timer?.cancel();
    _draftTimer?.cancel();
    if (_channel != null) {
      client?.removeChannel(_channel!);
      _channel = null;
    }
    me = null;
    passwordResetRequired = false;
    protectScreen = false;
    appLock = false;
    locked = false;
    preview = false;
    chats.clear();
    messages.clear();
    drafts.clear();
    cursors.clear();
    blocked.clear();
    signalStore = null;
    deviceId = null;
    _revision = 0;
    hidden.clear();
    _dirtyDrafts.clear();
    offline = false;
    _attempt = 0;
    _syncAgain = false;
    _uploadRetry = DateTime(2000);
    error = null;
    activeChat = null;
  }

  void openPreview() {
    _clear();
    preview = true;
    me = const Person(id: 'preview', username: 'you', name: 'Anda');
    const people = [
      Person(
        id: 'maya',
        username: 'maya_putri',
        name: 'Maya Putri',
        bio: 'One little adventure at a time.',
      ),
      Person(id: 'rizky', username: 'rizky_a', name: 'Rizky Aditya'),
      Person(id: 'nadia', username: 'nadia', name: 'Nadia Rahma'),
      Person(id: 'dimas', username: 'dimas_s', name: 'Dimas Saputra'),
    ];
    const snippets = [
      'Sampai ketemu besok, ya!',
      'Terima kasih! Sampai nanti.',
      'Ide yang bagus. Kita bahas nanti?',
      'Oke, aku tunggu kabarnya.',
    ];
    for (var i = 0; i < people.length; i++) {
      final chat = Conversation(
        id: 'sample-$i',
        peer: people[i],
        pinned: i == 0,
        unread: i == 0 ? 2 : 0,
      );
      chats.add(chat);
      messages.add(
        ChatMessage(
          id: 'sample-$i-1',
          chatId: chat.id,
          senderId: people[i].id,
          text: i == 0 ? 'Hai! Gimana kabarmu hari ini?' : snippets[i],
          at: DateTime.now().subtract(Duration(minutes: 12 + i * 47)),
          delivery: Delivery.delivered,
        ),
      );
      if (i == 0) {
        messages.add(
          ChatMessage(
            id: 'sample-0-2',
            chatId: chat.id,
            senderId: 'preview',
            text: 'Baik! Senang akhirnya punya tempat ngobrol di sini.',
            at: DateTime.now().subtract(const Duration(minutes: 10)),
            delivery: Delivery.read,
          ),
        );
        messages.add(
          ChatMessage(
            id: 'sample-0-3',
            chatId: chat.id,
            senderId: people[i].id,
            text: snippets[i],
            at: DateTime.now().subtract(const Duration(minutes: 8)),
            delivery: Delivery.delivered,
          ),
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _backupTimer?.cancel();
    _uploader.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _draftTimer?.cancel();
    _auth?.cancel();
    events.close();
    if (_channel != null) client?.removeChannel(_channel!);
    super.dispose();
  }
}
