import 'package:flutter/material.dart';
import '../app/widgets.dart';
import '../core/controller.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final password = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & riwayat chat')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              c.backupReady
                  ? Icons.cloud_done_outlined
                  : Icons.enhanced_encryption_outlined,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              c.backupStatus,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (c.backupSavedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Terakhir tersimpan: ${c.backupSavedAt!.toLocal().toString().substring(0, 16)}',
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Isi chat dan kunci lampiran dicadangkan terenkripsi ke database. Password login membuka backup saat masuk lagi setelah reinstall atau hapus data. Password tidak disimpan di aplikasi.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Jika password direset admin, gunakan password backup sebelumnya untuk membuka riwayat lama. Riwayat yang hilang sebelum backup aktif hanya dapat dipulihkan dari perangkat lain yang masih menyimpannya.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Password login / backup sebelumnya',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: c.backupBusy
                  ? null
                  : () async {
                      try {
                        await c.unlockHistory(password.text);
                        password.clear();
                        if (context.mounted) {
                          showNotice(
                            context,
                            'Riwayat dipulihkan dan backup terenkripsi aktif.',
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          showNotice(context, c.backupStatus);
                        }
                      }
                    },
              icon: const Icon(Icons.lock_open),
              label: Text(
                c.backupBusy
                    ? 'Membuka backup…'
                    : 'Aktifkan / pulihkan riwayat',
              ),
            ),
            if (c.backupReady) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: c.backupBusy
                    ? null
                    : () async {
                        try {
                          await c.matchBackupPassword(password.text);
                          password.clear();
                          if (context.mounted) {
                            showNotice(context, c.backupStatus);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            showNotice(
                              context,
                              'Masukkan password login saat ini. Buka backup lama terlebih dahulu.',
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.password),
                label: const Text('Samakan dengan password login'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: c.backupBusy
                    ? null
                    : () async {
                        try {
                          await c.backupNow();
                          if (context.mounted) {
                            showNotice(context, c.backupStatus);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            showNotice(context, c.backupStatus);
                          }
                        }
                      },
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Cadangkan sekarang'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
