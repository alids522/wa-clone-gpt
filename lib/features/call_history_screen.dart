import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../app/widgets.dart';
import '../core/call_record.dart';
import '../core/call_service.dart';
import '../core/controller.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key, required this.controller, this.service});
  final ChatController controller;
  final CallService? service;
  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final records = <CallRecord>[];
  bool loading = true, more = true, failed = false;
  Timer? timer;
  String get cacheKey => 'call_log_${widget.controller.me!.id}';
  @override
  void initState() {
    super.initState();
    _start();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (widget.controller.foreground) _load();
    });
  }

  Future<void> _start() async {
    try {
      final cached = await widget.controller.vault.read(cacheKey);
      if (mounted && cached != null) {
        setState(() {
          records.addAll(
            (jsonDecode(cached) as List).map(
              (r) => CallRecord(Map<String, dynamic>.from(r)),
            ),
          );
        });
      }
    } catch (_) {}
    await _load();
  }

  bool _fetching = false;
  Future<void> _load({bool next = false}) async {
    if (_fetching || widget.controller.preview) {
      if (mounted && loading) setState(() => loading = false);
      return;
    }
    _fetching = true;
    try {
      final offset = next ? records.length : 0;
      final rows = await widget.controller.client!
          .from('calls')
          .select()
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + 49)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        if (!next) records.clear();
        for (final row in rows) {
          if (!records.any((r) => r.id == row['id'])) {
            records.add(CallRecord(row));
          }
        }
        more = rows.length == 50;
        failed = false;
      });
      await widget.controller.vault.write(
        cacheKey,
        jsonEncode(records.take(50).map((r) => r.data).toList()),
      );
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      _fetching = false;
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (loading && records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (failed)
            ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Riwayat belum diperbarui'),
              trailing: IconButton(
                tooltip: 'Coba lagi',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 45),
              child: EmptyState(
                icon: Icons.call_outlined,
                title: 'Belum ada panggilan',
                body:
                    'Panggilan suara dan video tersimpan di akunmu, termasuk panggilan tak terjawab.',
              ),
            ),
          for (final record in records)
            Builder(
              builder: (context) {
                final room = c.chats
                    .where((room) => room.id == record.chatId)
                    .firstOrNull;
                final missed = !record.outgoing(c.me!.id) && record.unanswered;
                final color = missed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary;
                final at = record.at;
                final date =
                    '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
                Future<void> callback() async {
                  if (room == null || widget.service == null) return;
                  try {
                    await widget.service!.start(room, withVideo: record.video);
                  } catch (_) {
                    if (context.mounted) {
                      showNotice(
                        context,
                        'Panggilan belum dapat dimulai. Coba lagi.',
                      );
                    }
                  }
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: room == null
                      ? const CircleAvatar(child: Icon(Icons.person_outline))
                      : Avatar(room.peer, radius: 23),
                  title: Text(
                    room?.peer.name ?? 'Kontak',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: missed ? color : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            record.outgoing(c.me!.id)
                                ? Icons.call_made
                                : missed
                                ? Icons.call_missed
                                : Icons.call_received,
                            size: 15,
                            color: color,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '${record.video ? 'Video' : 'Suara'} · ${record.label(c.me!.id)}${record.duration == null ? '' : ' · ${record.duration}'}',
                            ),
                          ),
                        ],
                      ),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  onTap: room == null ? null : callback,
                  trailing: IconButton(
                    tooltip: record.video
                        ? 'Panggil video kembali'
                        : 'Telepon kembali',
                    onPressed: room == null ? null : callback,
                    icon: Icon(
                      record.video
                          ? Icons.videocam_outlined
                          : Icons.call_outlined,
                    ),
                  ),
                );
              },
            ),
          if (more && records.isNotEmpty)
            TextButton(
              onPressed: () => _load(next: true),
              child: const Text('Muat panggilan sebelumnya'),
            ),
        ],
      ),
    );
  }
}
