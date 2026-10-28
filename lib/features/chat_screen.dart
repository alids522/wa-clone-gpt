import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/call_service.dart';
import '../core/media_service.dart';
import 'media_widgets.dart';
import 'attachment_composer.dart';
import 'devices_screen.dart';

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
  ChatMessage? reply;
  RealtimeChannel? presence;
  Timer? typingExpiry;
  DateTime lastTyping = DateTime(2000);
  bool typing = false;
  @override
  void initState() {
    super.initState();
    composer = TextEditingController(
      text: widget.controller.drafts[widget.chat.id] ?? '',
    );
    widget.controller.activeChat = widget.chat.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.markRead(widget.chat);
    });
    if (!widget.controller.preview) {
      presence =
          widget.controller.client!.channel(
              'chat:${widget.chat.id}',
              opts: const RealtimeChannelConfig(private: true),
            )
            ..onBroadcast(
              event: 'typing',
              callback: (payload) {
                if (payload['user'] != widget.chat.peer.id ||
                    widget.controller.blocked.contains(widget.chat.peer.id) ||
                    !mounted) {
                  return;
                }
                setState(() => typing = payload['typing'] == true);
                typingExpiry?.cancel();
                typingExpiry = Timer(const Duration(seconds: 5), () {
                  if (mounted) setState(() => typing = false);
                });
              },
            )
            ..subscribe();
    }
  }

  @override
  void dispose() {
    widget.controller.activeChat = null;
    typingExpiry?.cancel();
    if (presence != null) widget.controller.client!.removeChannel(presence!);
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
      await widget.controller.send(
        widget.chat,
        text,
        data: {
          if (reply != null)
            'reply': {
              'id': reply!.id,
              'text': reply!.displayText.length > 160
                  ? reply!.displayText.substring(0, 160)
                  : reply!.displayText,
            },
        },
      );
      if (mounted) setState(() => reply = null);
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
          ).scale(36).clamp(56, 96),
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
                        typing ? 'Sedang mengetik…' : '@${chat.peer.username}',
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
            IconButton(
              tooltip: 'Panggilan suara',
              onPressed: () => _call(false),
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              tooltip: 'Panggilan video',
              onPressed: () => _call(true),
              icon: const Icon(Icons.videocam_outlined),
            ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                          : 'Pesan dan lampiran dienkripsi di perangkat',
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
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
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
                            padding: const EdgeInsets.only(bottom: 5),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    (MediaQuery.sizeOf(context).width * .86)
                                        .clamp(0, 520),
                              ),
                              child: GestureDetector(
                                onLongPress: () => _messageActions(m),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    7,
                                    8,
                                    5,
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
                                      if (m.data['reply'] != null && !m.deleted)
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black12,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '↪ ${m.data['reply']['text']}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      if (m.kind != 'text' && !m.deleted)
                                        AttachmentBubble(
                                          key: ValueKey(m.id),
                                          controller: c,
                                          message: m,
                                        ),
                                      if (m.kind == 'text' || m.deleted)
                                        Text(
                                          m.displayText,
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
                                      if (m.editedText != null && !m.deleted)
                                        const Text(
                                          'diedit',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                      if (m.reactions.isNotEmpty)
                                        Text(m.reactions.values.join(' ')),
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
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
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
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (reply != null)
                            ListTile(
                              dense: true,
                              title: const Text('Membalas'),
                              subtitle: Text(
                                reply!.displayText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Batal membalas',
                                onPressed: () => setState(() => reply = null),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Lampiran',
                                onPressed: sending ? null : _attach,
                                icon: const Icon(Icons.attach_file),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: composer,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: 10000,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Tulis pesan…',
                                    counterText: '',
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    c.setDraft(chat.id, value);
                                    if (!blocked &&
                                        DateTime.now()
                                                .difference(lastTyping)
                                                .inMilliseconds >
                                            1500) {
                                      lastTyping = DateTime.now();
                                      presence
                                          ?.sendBroadcastMessage(
                                            event: 'typing',
                                            payload: {
                                              'user': c.me!.id,
                                              'typing': value.isNotEmpty,
                                            },
                                          )
                                          .then<void>((_) {})
                                          .catchError((Object _) {});
                                    }
                                  },
                                  onSubmitted: (_) => send(),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Pesan suara',
                                onPressed: sending
                                    ? null
                                    : () => showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => VoiceRecorderSheet(
                                          controller: c,
                                          chat: chat,
                                        ),
                                      ),
                                icon: const Icon(Icons.mic_none),
                              ),
                              const SizedBox(width: 4),
                              IconButton.filled(
                                tooltip: 'Kirim pesan',
                                style: IconButton.styleFrom(
                                  backgroundColor: brand,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: sending ? null : send,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                            ],
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
  Future<void> _call(bool video) async {
    try {
      final service = CallService.of(widget.controller);
      if (service.active) {
        service.onShow?.call();
        return;
      }
      await service.start(widget.chat, withVideo: video);
    } catch (_) {
      if (mounted) showNotice(context, 'Panggilan tersedia setelah masuk.');
    }
  }

  Future<void> _attach() =>
      composeAttachments(context, widget.controller, widget.chat);

  Future<void> _react(ChatMessage m) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🙏', ''])
              TextButton(
                onPressed: () => Navigator.pop(context, emoji),
                child: Text(
                  emoji.isEmpty ? 'Hapus' : emoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
          ],
        ),
      ),
    );
    if (emoji != null) {
      await widget.controller.control(widget.chat, m, 'reaction', value: emoji);
    }
  }

  Future<void> _edit(ChatMessage m) async {
    final field = TextEditingController(text: m.displayText);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit pesan'),
        content: TextField(controller: field, maxLength: 10000, maxLines: 5),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    field.dispose();
    if (text != null) {
      await widget.controller.control(widget.chat, m, 'edit', value: text);
    }
  }

  Future<void> _forward(ChatMessage m) async {
    final target = await showModalBottomSheet<Conversation>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SectionLabel('Teruskan ke'),
            for (final c in widget.controller.chats)
              ListTile(
                title: Text(c.peer.name),
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      if (m.kind == 'text') {
        await widget.controller.send(
          target,
          m.displayText,
          data: {'forwarded': true},
        );
      } else {
        final file = await MediaService.download(widget.controller, m);
        try {
          await MediaService.send(
            widget.controller,
            target,
            file,
            m.data['name'],
            voice: m.kind == 'voice',
            duration: m.data['duration'],
          );
        } finally {
          if (await file.exists()) await file.delete();
        }
      }
      if (mounted) showNotice(context, 'Pesan diteruskan.');
    } catch (_) {
      if (mounted) showNotice(context, 'Belum dapat meneruskan pesan.');
    }
  }

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
              leading: const Icon(Icons.reply),
              title: const Text('Balas'),
              onTap: () {
                Navigator.pop(context);
                setState(() => reply = m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('Reaksi'),
              onTap: () {
                Navigator.pop(context);
                _react(m);
              },
            ),
            if (m.senderId == widget.controller.me!.id &&
                m.kind == 'text' &&
                !m.deleted)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit pesan'),
                onTap: () {
                  Navigator.pop(context);
                  _edit(m);
                },
              ),
            if (m.senderId == widget.controller.me!.id && !m.deleted)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Hapus untuk semua'),
                onTap: () async {
                  Navigator.pop(context);
                  if (await confirmAction(
                    this.context,
                    'Hapus untuk semua?',
                    'Penghapusan dikirim ke perangkat penerima. Salinan yang sudah disimpan di luar aplikasi tetap bisa ada.',
                  )) {
                    await widget.controller.control(widget.chat, m, 'delete');
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Hapus untuk saya'),
              onTap: () {
                Navigator.pop(context);
                widget.controller.hideMessage(m.id);
              },
            ),
            if (!m.deleted)
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Teruskan'),
                onTap: () {
                  Navigator.pop(context);
                  _forward(m);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Salin teks'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m.text));
                Navigator.pop(context);
              },
            ),
            if (m.delivery == Delivery.queued)
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Batalkan antrean'),
                onTap: () {
                  Navigator.pop(context);
                  widget.controller.cancelQueued(m.id);
                },
              ),
            if (m.delivery == Delivery.failed && m.data['_cancelled'] != true)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Coba kirim lagi'),
                onTap: () {
                  widget.controller.retryMessage(m.id);
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.verified_user_outlined, color: ice),
                title: Text('Verifikasi keamanan'),
                subtitle: const Text('Bandingkan nomor keamanan kedua akun.'),
                onTap: () => Navigator.push(
                  this.context,
                  MaterialPageRoute<void>(
                    builder: (_) => SafetyScreen(
                      controller: widget.controller,
                      chat: widget.chat,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Laporkan kontak'),
                onTap: () {
                  Navigator.pop(context);
                  _report();
                },
              ),
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

  Future<void> _report() async {
    final reason = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Laporkan kontak'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Alasan ini dapat dibaca administrator. Isi chat tidak dilampirkan otomatis.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              maxLength: 1000,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Alasan laporan'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reason.text.trim()),
            child: const Text('Kirim laporan'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (text == null || text.isEmpty) return;
    try {
      await widget.controller.client!.rpc(
        'submit_report',
        params: {'chat': widget.chat.id, 'reason': text},
      );
      if (mounted) showNotice(context, 'Laporan dikirim ke administrator.');
    } catch (_) {
      if (mounted) {
        showNotice(context, 'Laporan belum dapat dikirim. Coba lagi nanti.');
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
