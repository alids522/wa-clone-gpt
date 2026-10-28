import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'models.dart';
import 'push_service.dart';
import 'signal_store.dart';
import 'vault.dart';

class ChatController extends ChangeNotifier {
  ChatController({required this.vault, this.client});
  final Vault vault;
  final SupabaseClient? client;
  ThemeMode theme = ThemeMode.system;
  Person? me;
  bool preview = false, busy = false, offline = false, readReceipts = true;
  String? error;
  final List<Conversation> chats = [];
  final List<ChatMessage> messages = [];
  final Map<String, String> drafts = {};
  final Set<String> blocked = {};
  final Map<String, String> cursors = {};
  PersistentSignalStore? signalStore;
  Timer? _timer;
  Timer? _draftTimer;
  StreamSubscription<AuthState>? _auth;
  RealtimeChannel? _channel;
  Future<void> _serial = Future.value();
  Future<void> _writes = Future.value();
  DateTime _nextRetry = DateTime(2000);
  int _attempt = 0;
  bool _syncing = false, _disposed = false;
  String? activeChat;
  bool get configured => client != null;
  bool get isAdmin => me?.role == 'admin' && me?.status == 'active' && !preview;
  void notifyPreferences() => notifyListeners();
  void setDraft(String chatId, String value) {
    drafts[chatId] = value;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      persist().catchError((Object _) {
        error = 'Draf belum tersimpan. Periksa penyimpanan perangkat.';
        if (!_disposed) notifyListeners();
      });
    });
  }

  List<ChatMessage> inChat(String id) =>
      messages.where((m) => m.chatId == id && m.kind == 'text').toList()
        ..sort((a, b) {
          final time = a.at.compareTo(b.at);
          return time == 0 ? a.id.compareTo(b.id) : time;
        });

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    theme = ThemeMode.values.firstWhere(
      (t) => t.name == prefs.getString('theme'),
      orElse: () => ThemeMode.system,
    );
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
    } on AuthException {
      error =
          'Username/email atau password tidak sesuai, atau kode undangan tidak dapat digunakan.';
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

  Future<void> _openAccount() async {
    final uid = client!.auth.currentUser!.id;
    final state = await readJson(vault, 'account_$uid');
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
    signalStore = state['crypto'] == null
        ? await PersistentSignalStore.create()
        : PersistentSignalStore(Map<String, dynamic>.from(state['crypto']));
    await persist(); // Retain identity before publishing public keys.
    if (!offline) {
      await client!
          .rpc(
            'register_device',
            params: {'bundle': await signalStore!.publicBundle()},
          )
          .timeout(const Duration(seconds: 20));
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
  }

  // UI preference/draft writes must wait for a whole crypto transaction.
  // Otherwise a timer could persist an advanced ratchet before its envelope.
  Future<void> persist() => _exclusive(_commit);

  Future<void> _commit() async {
    if (preview || me == null) return;
    final key = 'account_${me!.id}';
    final snapshot = jsonEncode({
      'me': me!.toJson(),
      'chats': chats.map((c) => c.toJson()).toList(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'drafts': drafts,
      'cursors': cursors,
      'blocked': blocked.toList(),
      'read_receipts': readReceipts,
      'crypto': signalStore?.data,
    });
    final write = _writes.then((_) => vault.write(key, snapshot));
    _writes = write.catchError((Object _) {});
    await write;
  }

  Future<void> _exclusive(Future<void> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.catchError((Object _) {});
    return result;
  }

  Future<void> sync() async {
    if (preview || me == null || _syncing || _disposed) return;
    _syncing = true;
    try {
      await _exclusive(() async {
        final current = await client!
            .rpc('my_account')
            .timeout(const Duration(seconds: 15));
        if (current['status'] != 'active') {
          await client!.auth.signOut();
          _clear();
          return;
        }
        me = Person(
          id: me!.id,
          username: me!.username,
          name: me!.name,
          bio: me!.bio,
          role: current['role'],
          status: current['status'],
        );
        final rows = await client!.rpc('list_chats');
        for (final row in rows as List) {
          if (!chats.any((c) => c.id == row['id'])) {
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
            final events = await client!.rpc(
              'sync_messages',
              params: {
                'chat': chat.id,
                'after_sequence': int.tryParse(cursors[chat.id] ?? '') ?? 0,
              },
            );
            more = (events as List).length == 50;
            for (final row in events) {
              final sequence = row['sequence'].toString();
              if (row['sender_id'] == me!.id) {
                for (final m in messages.where(
                  (m) => m.id == row['client_message_id'],
                )) {
                  m.serverId = row['id'];
                  m.at = DateTime.parse(row['created_at']);
                  if (m.delivery == Delivery.queued ||
                      m.delivery == Delivery.failed) {
                    m.delivery = Delivery.sent;
                  }
                }
              } else if (!messages.any((m) => m.serverId == row['id'])) {
                final envelope = Map<String, dynamic>.from(row['ciphertext']);
                final before = jsonEncode(signalStore!.data);
                final beforeLength = messages.length;
                final unread = chat.unread;
                final statuses = {for (final m in messages) m.id: m.delivery};
                try {
                  final content = jsonDecode(
                    await SignalEngine(
                      signalStore!,
                    ).decrypt(chat.peer.id, envelope),
                  );
                  if (content['chat'] != chat.id ||
                      content['sender'] != row['sender_id'] ||
                      content['id'] != row['client_message_id']) {
                    throw StateError('Invalid message binding');
                  }
                  messages.add(
                    ChatMessage(
                      id: row['client_message_id'],
                      serverId: row['id'],
                      chatId: chat.id,
                      senderId: row['sender_id'],
                      text: content['text'],
                      at: DateTime.parse(row['created_at']),
                      delivery: Delivery.delivered,
                      kind: content['kind'] ?? 'text',
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
                          m.kind == 'text' &&
                          (receipt['ids'] as List).contains(m.id),
                    )) {
                      final next = Delivery.values.byName(receipt['state']);
                      if (next.index > m.delivery.index ||
                          m.delivery == Delivery.failed) {
                        m.delivery = next;
                      }
                    }
                  } else if ((content['kind'] ?? 'text') == 'text') {
                    if (activeChat != chat.id) chat.unread++;
                    _queueReceipt(
                      chat.id,
                      [row['client_message_id'] as String],
                      activeChat == chat.id && readReceipts
                          ? 'read'
                          : 'delivered',
                    );
                    if (activeChat == chat.id && readReceipts) {
                      messages
                              .firstWhere((m) => m.serverId == row['id'])
                              .delivery =
                          Delivery.read;
                    }
                  } else {
                    throw StateError('Unsupported event');
                  }
                  await _commit(); // Commit received plaintext + ratchet before advancing cursor or ACK.
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
    } catch (_) {
      offline = true;
      _attempt = min(_attempt + 1, 6);
      _nextRetry = DateTime.now().add(
        Duration(seconds: min(120, 1 << _attempt) + Random.secure().nextInt(4)),
      );
    } finally {
      _syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> send(Conversation chat, String text) async {
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
          at: DateTime.now(),
        ),
      );
      drafts.remove(chat.id);
      try {
        await _commit();
      } catch (_) {
        messages.removeLast();
        rethrow;
      }
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
    chat.unread = 0;
    if (preview || !readReceipts) return;
    await _exclusive(() async {
      final unread = messages
          .where(
            (m) =>
                m.chatId == chat.id &&
                m.senderId == chat.peer.id &&
                m.kind == 'text' &&
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
    blocked.add(peer.id);
    await persist();
    notifyListeners();
  }

  Future<void> logout() async {
    await _serial;
    await PushService.stop();
    if (!preview) {
      await persist();
      await client?.auth.signOut();
    }
    _clear();
    notifyListeners();
  }

  void _clear() {
    _timer?.cancel();
    _draftTimer?.cancel();
    if (_channel != null) {
      client?.removeChannel(_channel!);
      _channel = null;
    }
    me = null;
    preview = false;
    chats.clear();
    messages.clear();
    drafts.clear();
    cursors.clear();
    blocked.clear();
    signalStore = null;
    offline = false;
    _attempt = 0;
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
    _timer?.cancel();
    _draftTimer?.cancel();
    _auth?.cancel();
    if (_channel != null) client?.removeChannel(_channel!);
    super.dispose();
  }
}
