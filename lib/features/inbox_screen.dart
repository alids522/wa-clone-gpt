import 'package:flutter/material.dart';
import '../app/theme.dart';
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(
          context,
        ).scale(60).clamp(84, 140),
        titleSpacing: 24,
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
                fontSize: 28,
                letterSpacing: -.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
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
          if (c.preview || c.offline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                        child: TextField(
                          onChanged: (s) => setState(() => query = s),
                          decoration: const InputDecoration(
                            hintText: 'Cari percakapan',
                            prefixIcon: Icon(Icons.search_rounded),
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (var i = 0; i < 3; i++)
                                ChoiceChip(
                                  label: Text(
                                    ['Semua', 'Belum dibaca', 'Disematkan'][i],
                                  ),
                                  selected: filter == i,
                                  showCheckmark: false,
                                  onSelected: (_) => setState(() => filter = i),
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
                                            left: 96,
                                            right: 24,
                                          ),
                                          child: Divider(height: 1),
                                        ),
                                  itemBuilder: (context, index) {
                                    if (index == chats.length) {
                                      return Padding(
                                        padding: const EdgeInsets.all(28),
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
                                                style: TextStyle(fontSize: 11),
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
                                            horizontal: 24,
                                            vertical: 10,
                                          ),
                                      leading: Avatar(chat.peer),
                                      minLeadingWidth: 58,
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
                                            last == null ? '' : _time(last.at),
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
                                        padding: const EdgeInsets.only(top: 7),
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
                                                last?.text ??
                                                    'Kirim sapaan pertama',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  '${chat.unread}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
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
    );
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
                setState(() => chat.pinned = !chat.pinned);
                widget.controller.persist();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: Text(
                chat.muted ? 'Aktifkan notifikasi' : 'Bisukan percakapan',
              ),
              onTap: () {
                setState(() => chat.muted = !chat.muted);
                widget.controller.persist();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
