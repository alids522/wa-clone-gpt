import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller, required this.chat});
  final ChatController controller;
  final Conversation chat;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final TextEditingController composer;
  final scroll = ScrollController();
  bool sending = false;
  @override
  void initState() {
    super.initState();
    composer = TextEditingController(
      text: widget.controller.drafts[widget.chat.id] ?? '',
    );
    widget.controller.activeChat = widget.chat.id;
    widget.controller.markRead(widget.chat);
  }

  @override
  void dispose() {
    widget.controller.activeChat = null;
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || composer.text.trim().isEmpty) return;
    final text = composer.text;
    setState(() {
      sending = true;
      composer.clear();
    });
    try {
      await widget.controller.send(widget.chat, text);
    } catch (_) {
      if (mounted) {
        composer.text = text;
        showNotice(
          context,
          'Berhasil menyimpan? Periksa antrean sebelum mencoba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, chat = widget.chat;
      final messages = c.inChat(chat.id).reversed.toList();
      final blocked = c.blocked.contains(chat.peer.id);
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(
            context,
          ).scale(40).clamp(64, 100),
          titleSpacing: 0,
          title: InkWell(
            onTap: _profile,
            child: Row(
              children: [
                Avatar(chat.peer, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.peer.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${chat.peer.username}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Opsi percakapan',
              onSelected: (s) {
                if (s == 'profile') _profile();
                if (s == 'block') _block();
                if (s == 'search') _search();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Text('Info kontak & keamanan'),
                ),
                const PopupMenuItem(
                  value: 'search',
                  child: Text('Cari dalam percakapan'),
                ),
                if (!blocked)
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('Blokir kontak'),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: ice),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      c.preview
                          ? 'Contoh percakapan · hanya di perangkat ini'
                          : 'Signal Protocol · prototipe belum diaudit',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (c.offline)
              const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Tidak ada koneksi. Pesan menunggu sinkronisasi.',
                  style: TextStyle(color: ice, fontSize: 12),
                ),
              ),
            Expanded(
              child: messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.waving_hand_outlined,
                      title: 'Mulai dengan sapaan',
                      body: 'Tulis pesan pertamamu di bawah.',
                    )
                  : ListView.builder(
                      controller: scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        final mine = m.senderId == c.me!.id;
                        final t = m.at.toLocal();
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .78,
                              ),
                              child: GestureDetector(
                                onLongPress: () => _messageActions(m),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    12,
                                    9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? const Color(0xFF1D4ED8)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(20),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: Radius.circular(
                                        mine ? 20 : 5,
                                      ),
                                      bottomRight: Radius.circular(
                                        mine ? 5 : 20,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        m.text,
                                        style: TextStyle(
                                          color: mine
                                              ? Colors.white
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                          fontSize: 15,
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: mine
                                                  ? const Color(0xFFDCE9FF)
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                          ),
                                          if (mine) ...[
                                            const SizedBox(width: 5),
                                            Semantics(
                                              label: _deliveryLabel(m.delivery),
                                              child: Icon(
                                                switch (m.delivery) {
                                                  Delivery.queued =>
                                                    Icons.schedule_rounded,
                                                  Delivery.sent =>
                                                    Icons.check_rounded,
                                                  Delivery.delivered ||
                                                  Delivery.read =>
                                                    Icons.done_all_rounded,
                                                  Delivery.failed =>
                                                    Icons.error_outline_rounded,
                                                },
                                                size: 14,
                                                color:
                                                    m.delivery == Delivery.read
                                                    ? const Color(0xFFB2E9FF)
                                                    : Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: blocked
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Kontak diblokir. Pesan baru tidak dapat dikirim.',
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: composer,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 10000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Tulis pesan…',
                                counterText: '',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                              ),
                              onChanged: (value) {
                                c.setDraft(chat.id, value);
                              },
                              onSubmitted: (_) => send(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            tooltip: 'Kirim pesan',
                            style: IconButton.styleFrom(
                              backgroundColor: brand,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(52, 52),
                            ),
                            onPressed: sending ? null : send,
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );
  String _deliveryLabel(Delivery value) => switch (value) {
    Delivery.queued => 'Menunggu koneksi',
    Delivery.sent => 'Diterima server',
    Delivery.delivered => 'Tersimpan di perangkat penerima',
    Delivery.read => 'Dibaca',
    Delivery.failed => 'Gagal dikirim',
  };
  void _messageActions(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Salin teks'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m.text));
                Navigator.pop(context);
              },
            ),
            if (m.delivery == Delivery.failed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Coba kirim lagi'),
                onTap: () {
                  m.delivery = Delivery.queued;
                  widget.controller.persist();
                  widget.controller.sync();
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_deliveryLabel(m.delivery)),
            ),
          ],
        ),
      ),
    );
  }

  void _profile() {
    final p = widget.chat.peer;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(p, radius: 42),
              const SizedBox(height: 18),
              Text(
                p.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text('@${p.username}', style: const TextStyle(color: ice)),
              if (p.bio.isNotEmpty)
                Padding(padding: const EdgeInsets.all(20), child: Text(p.bio)),
              const SizedBox(height: 20),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.verified_user_outlined, color: ice),
                title: Text('Verifikasi keamanan'),
                subtitle: Text(
                  'Identitas yang berubah akan menahan pengiriman. Verifikasi QR dan persetujuan kunci baru menunggu pengujian keamanan.',
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _block();
                },
                icon: const Icon(Icons.block),
                label: const Text('Blokir kontak'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _block() async {
    if (await confirmAction(
      context,
      'Blokir kontak?',
      'Pesan baru dari kontak ini akan ditolak. Riwayat lokal tetap disimpan.',
    )) {
      try {
        await widget.controller.block(widget.chat.peer);
      } catch (_) {
        if (mounted) showNotice(context, 'Belum dapat memblokir. Coba lagi.');
      }
    }
  }

  Future<void> _search() async {
    final query = TextEditingController();
    final term = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cari pesan lokal'),
        content: TextField(
          controller: query,
          autofocus: true,
          onSubmitted: (s) => Navigator.pop(context, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, query.text),
            child: const Text('Cari'),
          ),
        ],
      ),
    );
    query.dispose();
    if (term == null || term.isEmpty || !mounted) return;
    final result = widget.controller
        .inChat(widget.chat.id)
        .where((m) => m.text.toLowerCase().contains(term.toLowerCase()))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: result.isEmpty
              ? const EmptyState(
                  icon: Icons.search,
                  title: 'Tidak ada hasil',
                  body:
                      'Pencarian hanya dilakukan pada pesan di perangkat ini.',
                )
              : ListView(
                  children: [
                    const SectionLabel('Hasil pencarian lokal'),
                    for (final m in result)
                      ListTile(
                        title: Text(m.text),
                        subtitle: Text(
                          m.at.toLocal().toString().substring(0, 16),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
