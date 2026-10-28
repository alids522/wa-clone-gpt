import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/widgets.dart';
import '../core/controller.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.controller.client!.functions.invoke(
        'admin',
        body: {'action': tab == 0 ? 'list-users' : 'audit'},
      );
      if (mounted) {
        setState(
          () => rows = (result.data['rows'] as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Akses ditolak atau layanan belum tersedia.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> action(String action, String? target) async {
    final reason = TextEditingController(), password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'create-invite' ? 'Buat undangan' : 'Konfirmasi tindakan',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action == 'suspend'
                    ? 'Akun ini tidak dapat mengirim pesan setelah dinonaktifkan.'
                    : action == 'force-reset'
                    ? 'Sesi akan dicabut dan akun dibatasi hingga reset diselesaikan administrator. Riwayat E2EE tidak dipulihkan.'
                    : 'Masukkan alasan dan autentikasi ulang untuk melanjutkan.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Alasan tindakan'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password administrator',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty && password.text.isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Konfirmasi'),
          ),
        ],
      ),
    );
    if (ok != true) {
      reason.dispose();
      password.dispose();
      return;
    }
    try {
      final response = await widget.controller.client!.functions.invoke(
        'admin',
        body: {
          'action': action,
          'target': target,
          'reason': reason.text.trim(),
          'password': password.text,
        },
      );
      if (!mounted) return;
      if (response.data['invite_code'] != null) {
        final code = response.data['invite_code'] as String;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Undangan dibuat'),
            content: SelectableText(
              '$code\n\nSatu kali pakai • berlaku 7 hari. Simpan sekarang; kode tidak dapat dilihat lagi.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  Navigator.pop(context);
                },
                child: const Text('Salin & tutup'),
              ),
            ],
          ),
        );
      }
      await load();
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Tindakan ditolak. Periksa otorisasi dan coba lagi.',
        );
      }
    } finally {
      reason.dispose();
      password.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => !widget.controller.isAdmin
        ? Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Akses dibatasi',
              body: 'Panel ini hanya untuk administrator aktif.',
            ),
          )
        : Scaffold(
            appBar: AppBar(
              title: const Text('Administrasi'),
              actions: [
                IconButton(
                  tooltip: 'Buat undangan',
                  onPressed: () => action('create-invite', null),
                  icon: const Icon(Icons.add_link),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Pengguna')),
                      ButtonSegment(value: 1, label: Text('Audit log')),
                    ],
                    selected: {tab},
                    onSelectionChanged: (s) {
                      tab = s.first;
                      load();
                    },
                  ),
                ),
                if (loading) const LinearProgressIndicator(),
                Expanded(
                  child: error != null
                      ? EmptyState(
                          icon: Icons.error_outline,
                          title: 'Belum dapat memuat',
                          body: error!,
                          action: FilledButton(
                            onPressed: load,
                            child: const Text('Coba lagi'),
                          ),
                        )
                      : rows.isEmpty && !loading
                      ? const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Belum ada data',
                          body: 'Aktivitas akan muncul di sini.',
                        )
                      : RefreshIndicator(
                          onRefresh: load,
                          child: ListView(
                            children: [
                              for (final row in rows)
                                ListTile(
                                  title: Text(
                                    (tab == 0
                                            ? row['username']
                                            : row['action']) ??
                                        '',
                                  ),
                                  subtitle: Text(
                                    tab == 0
                                        ? '${row['role']} · ${row['status']}'
                                        : '${row['created_at']}\n${row['reason'] ?? ''}',
                                  ),
                                  trailing:
                                      tab == 0 &&
                                          row['id'] != widget.controller.me!.id
                                      ? PopupMenuButton<String>(
                                          onSelected: (s) =>
                                              action(s, row['id']),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value:
                                                  row['status'] == 'suspended'
                                                  ? 'unsuspend'
                                                  : 'suspend',
                                              child: Text(
                                                row['status'] == 'suspended'
                                                    ? 'Aktifkan akun'
                                                    : 'Nonaktifkan akun',
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'force-reset',
                                              child: Text(
                                                'Paksa reset password',
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
  );
}
