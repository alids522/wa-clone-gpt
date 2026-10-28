import 'dart:async';
import 'package:flutter/material.dart';
import '../core/call_service.dart';
import '../core/push_service.dart';
import 'package:device_runtime/device_runtime.dart';
import 'call_screen.dart';
import '../app/theme.dart';
import '../app/root_back_guard.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'chat_screen.dart';
import 'people_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CallService? calls;
  StreamSubscription<String>? _navigation;
  bool _callVisible = false;
  @override
  void initState() {
    super.initState();
    if (!widget.controller.preview) {
      calls = CallService(widget.controller)..onShow = _showCall;
      _navigation = PushService.navigation.stream.listen(_openNotification);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (PushService.pendingChat != null) {
          _openNotification(PushService.pendingChat!);
        }
      });
    }
  }

  void _openNotification(String id) {
    if (!mounted) return;
    final chat = widget.controller.chats.where((c) => c.id == id).firstOrNull;
    if (chat == null) return;
    PushService.pendingChat = null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(controller: widget.controller, chat: chat),
      ),
    );
  }

  Future<void> _showCall() async {
    if (!mounted || _callVisible || calls == null) return;
    _callVisible = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CallScreen(service: calls!)),
    );
    _callVisible = false;
  }

  @override
  void dispose() {
    _navigation?.cancel();
    calls?.dispose();
    super.dispose();
  }

  int tab = 0, filter = 0;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final chats =
        c.chats
            .where(
              (chat) =>
                  (filter == 0 ||
                      (filter == 1 ? chat.unread > 0 : chat.pinned)) &&
                  ('${chat.peer.name} ${chat.peer.username} ${c.inChat(chat.id).lastOrNull?.text ?? ''}')
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return (c.inChat(b.id).lastOrNull?.at ?? DateTime(2000)).compareTo(
              c.inChat(a.id).lastOrNull?.at ?? DateTime(2000),
            );
          });
    return RootBackGuard(
      returnToChats: () {
        if (tab == 0) return false;
        setState(() => tab = 0);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(
            context,
          ).scale(40).clamp(60, 110),
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tab == 0 ? 'ADOETZ CHAT' : 'RUANG PRIVATMU',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                ['Percakapan', 'Kontak', 'Pengaturan'][tab],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: -.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            if (!c.preview)
              IconButton(
                tooltip: 'Riwayat panggilan',
                onPressed: _callHistory,
                icon: const Icon(Icons.call_outlined),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: IconButton(
                tooltip: 'Profil dan pengaturan',
                onPressed: () => setState(() => tab = 2),
                icon: Avatar(c.me!, radius: 20),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (calls != null)
              ListenableBuilder(
                listenable: calls!,
                builder: (context, _) => !calls!.active
                    ? const SizedBox.shrink()
                    : Material(
                        color: brand,
                        child: InkWell(
                          onTap: _showCall,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  calls!.video ? Icons.videocam : Icons.call,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Panggilan · ${calls!.chat?.peer.name ?? 'Adoetz Chat'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.open_in_full,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            if (PushService.configured && !c.preview)
              ValueListenableBuilder<PushState>(
                valueListenable: PushService.status,
                builder: (context, state, _) => state == PushState.ready
                    ? const SizedBox.shrink()
                    : MaterialBanner(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        content: Text(
                          PushService.explanation,
                          style: const TextStyle(fontSize: 12),
                        ),
                        actions: [
                          TextButton(
                            onPressed: state == PushState.checking
                                ? null
                                : () async {
                                    final enabled = await PushService.enable(c);
                                    if (!enabled && context.mounted) {
                                      if (PushService.status.value ==
                                          PushState.permissionNeeded) {
                                        await DeviceRuntime.openNotificationSettings();
                                      } else {
                                        showNotice(
                                          context,
                                          PushService.explanation,
                                        );
                                      }
                                    }
                                  },
                            child: Text(
                              state == PushState.checking
                                  ? 'Menyiapkan…'
                                  : 'Aktifkan',
                            ),
                          ),
                        ],
                      ),
              ),
            if (c.preview || c.offline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                color: brand.withValues(alpha: .12),
                child: Row(
                  children: [
                    Icon(
                      c.preview
                          ? Icons.science_outlined
                          : Icons.cloud_off_outlined,
                      size: 16,
                      color: ice,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.preview
                            ? 'Pratinjau lokal · pesan tidak dikirim'
                            : 'Offline · pesan menunggu koneksi',
                        style: const TextStyle(fontSize: 12, color: ice),
                      ),
                    ),
                    if (c.offline)
                      IconButton(
                        tooltip: 'Sinkronkan kembali',
                        onPressed: c.sync,
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: tab == 1
                  ? PeopleScreen(controller: c)
                  : tab == 2
                  ? SettingsScreen(controller: c)
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: TextField(
                            onChanged: (s) => setState(() => query = s),
                            decoration: const InputDecoration(
                              hintText: 'Cari percakapan',
                              prefixIcon: Icon(Icons.search_rounded),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                for (var i = 0; i < 3; i++)
                                  ChoiceChip(
                                    label: Text(
                                      [
                                        'Semua',
                                        'Belum dibaca',
                                        'Disematkan',
                                      ][i],
                                    ),
                                    selected: filter == i,
                                    showCheckmark: false,
                                    onSelected: (_) =>
                                        setState(() => filter = i),
                                    side: BorderSide.none,
                                    selectedColor: brand.withValues(alpha: .2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: chats.isEmpty
                              ? EmptyState(
                                  icon: Icons.forum_outlined,
                                  title: query.isEmpty
                                      ? 'Mulai percakapan berarti'
                                      : 'Tidak ada percakapan',
                                  body: query.isEmpty
                                      ? 'Temukan teman melalui username.\nSatu sapaan bisa jadi awal yang baik.'
                                      : 'Coba kata pencarian atau filter lain.',
                                  action: query.isEmpty
                                      ? FilledButton(
                                          onPressed: () =>
                                              setState(() => tab = 1),
                                          child: const Text('Temukan teman'),
                                        )
                                      : null,
                                )
                              : RefreshIndicator(
                                  onRefresh: c.sync,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.only(bottom: 90),
                                    itemCount: chats.length + 1,
                                    separatorBuilder: (_, index) =>
                                        index == chats.length - 1
                                        ? const SizedBox.shrink()
                                        : const Padding(
                                            padding: EdgeInsets.only(
                                              left: 74,
                                              right: 16,
                                            ),
                                            child: Divider(height: 1),
                                          ),
                                    itemBuilder: (context, index) {
                                      if (index == chats.length) {
                                        return Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.lock_outline_rounded,
                                                size: 12,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 6),
                                              const Flexible(
                                                child: Text(
                                                  'Percakapanmu, ruang pribadimu.',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      final chat = chats[index],
                                          last = c
                                              .inChat(chats[index].id)
                                              .lastOrNull;
                                      return ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 2,
                                            ),
                                        leading: Avatar(chat.peer, radius: 23),
                                        minLeadingWidth: 44,
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                chat.peer.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              last == null
                                                  ? ''
                                                  : _time(last.at),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: chat.unread > 0
                                                    ? ice
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Row(
                                            children: [
                                              if (chat.muted)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    right: 4,
                                                  ),
                                                  child: Icon(
                                                    Icons.volume_off_outlined,
                                                    size: 14,
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  last?.displayText ??
                                                      'Kirim sapaan pertama',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                              if (chat.pinned)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 6,
                                                  ),
                                                  child: Icon(
                                                    Icons.push_pin_rounded,
                                                    size: 13,
                                                  ),
                                                ),
                                              if (chat.unread > 0)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: brand,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${chat.unread}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              controller: c,
                                              chat: chat,
                                            ),
                                          ),
                                        ),
                                        onLongPress: () => _chatActions(chat),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: tab == 0
            ? FloatingActionButton(
                tooltip: 'Percakapan baru',
                backgroundColor: brand,
                foregroundColor: Colors.white,
                onPressed: () => setState(() => tab = 1),
                child: const Icon(Icons.edit_square, size: 23),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          height: MediaQuery.textScalerOf(context).scale(48).clamp(64, 100),
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Kontak',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callHistory() async {
    try {
      final c = widget.controller;
      final rows = await c.client!
          .from('calls')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: rows.isEmpty
                ? const EmptyState(
                    icon: Icons.call_outlined,
                    title: 'Belum ada panggilan',
                    body: 'Riwayat panggilan akan tampil di sini.',
                  )
                : ListView(
                    children: [
                      const SectionLabel('Riwayat panggilan'),
                      for (final row in rows)
                        ListTile(
                          leading: Icon(
                            row['video'] == true
                                ? Icons.videocam_outlined
                                : Icons.call_outlined,
                          ),
                          title: Text(
                            c.chats
                                    .where(
                                      (r) => r.id == row['conversation_id'],
                                    )
                                    .firstOrNull
                                    ?.peer
                                    .name ??
                                'Kontak',
                          ),
                          subtitle: Text(
                            '${row['status']} · ${DateTime.parse(row['created_at']).toLocal().toString().substring(0, 16)}',
                          ),
                          onTap: () {
                            final room = c.chats
                                .where((r) => r.id == row['conversation_id'])
                                .firstOrNull;
                            Navigator.pop(context);
                            if (room != null) {
                              calls?.start(room, withVideo: row['video']);
                            }
                          },
                        ),
                    ],
                  ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) showNotice(context, 'Riwayat panggilan belum dapat dimuat.');
    }
  }

  String _time(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _chatActions(Conversation chat) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(
                chat.pinned ? 'Lepas sematan' : 'Sematkan percakapan',
              ),
              onTap: () {
                widget.controller.toggleChatPreference(chat, pin: true);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: Text(
                chat.muted ? 'Aktifkan notifikasi' : 'Bisukan percakapan',
              ),
              onTap: () {
                widget.controller.toggleChatPreference(chat, pin: false);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
