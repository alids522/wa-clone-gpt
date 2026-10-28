import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/push_service.dart';
import 'admin_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, me = controller.me!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Avatar(me, radius: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${me.username}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit profil',
                onPressed: () => _profile(context),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
            ],
          ),
        ),
        const SectionLabel('Personalisasi'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Tampilan'),
          subtitle: Text(switch (c.theme) {
            ThemeMode.system => 'Ikuti sistem',
            ThemeMode.dark => 'Midnight Blue',
            ThemeMode.light => 'Ice Blue',
          }),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _appearance(context),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.notifications_none_rounded),
          title: const Text('Notifikasi'),
          subtitle: const Text('Pratinjau pesan disembunyikan'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            try {
              final enabled = await PushService.enable(c);
              if (context.mounted) {
                showNotice(
                  context,
                  enabled
                      ? 'Notifikasi diaktifkan. Isi pesan tetap privat.'
                      : 'Notifikasi belum diizinkan. Kamu tetap dapat membuka chat.',
                );
              }
            } catch (_) {
              if (context.mounted) {
                showNotice(
                  context,
                  'Notifikasi belum tersedia. Konfigurasi Firebase sedang disiapkan.',
                );
              }
            }
          },
        ),
        const SectionLabel('Privasi & keamanan'),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          secondary: const Icon(Icons.done_all_rounded),
          title: const Text('Tanda dibaca'),
          subtitle: const Text('Bagikan saat pesan sudah dibuka'),
          value: c.readReceipts,
          onChanged: (value) {
            c.readReceipts = value;
            c.persist();
            c.notifyPreferences();
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.phonelink_lock_outlined),
          title: const Text('Perangkat & kunci'),
          subtitle: const Text('Satu identitas perangkat aktif'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Kunci tinggal di perangkatmu'),
              content: const Text(
                'Reset password tidak memulihkan pesan lama. Jangan hapus data aplikasi atau ganti perangkat bila kamu masih membutuhkan riwayat. Backup kunci dan perpindahan perangkat belum tersedia pada alpha ini.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Mengerti'),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.block_outlined),
          title: const Text('Kontak diblokir'),
          subtitle: Text('${c.blocked.length} kontak'),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            builder: (context) => SafeArea(
              child: c.blocked.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Belum ada kontak yang diblokir.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        const SectionLabel('Kontak diblokir'),
                        for (final chat in c.chats.where(
                          (chat) => c.blocked.contains(chat.peer.id),
                        ))
                          ListTile(
                            leading: Avatar(chat.peer),
                            title: Text(chat.peer.name),
                            subtitle: Text('@${chat.peer.username}'),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        if (c.isAdmin) ...[
          const SectionLabel('Administrasi'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(
              Icons.admin_panel_settings_outlined,
              color: ice,
            ),
            title: const Text('Panel administrator'),
            subtitle: const Text('Akun, undangan, dan audit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminScreen(controller: c)),
            ),
          ),
        ],
        const SectionLabel('Tentang'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('Adoetz Chat'),
          subtitle: const Text('0.1.0 alpha · prototipe internal'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Adoetz Chat',
            applicationVersion: '0.1.0 alpha',
            applicationIcon: const BrandMark(size: 48),
            children: const [
              Text(
                'Pesan privat, tetap simpel.\n\nPrototipe ini belum lulus audit E2EE dan pengujian dua perangkat. Jangan gunakan untuk data sensitif.\n\nServer memproses profil publik dan metadata transport. Isi pesan dienkripsi di perangkat. Panggilan, media, dan pemulihan kunci belum tersedia.',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: OutlinedButton.icon(
            onPressed: () async {
              if (await confirmAction(
                context,
                c.preview ? 'Keluar dari pratinjau?' : 'Keluar dari akun?',
                'Kunci perangkat dipertahankan. Pesan yang masih antre akan dilanjutkan saat akun ini masuk kembali.',
              )) {
                try {
                  await c.logout();
                } catch (_) {
                  if (context.mounted) {
                    showNotice(
                      context,
                      'Belum dapat keluar. Periksa koneksi lalu coba lagi.',
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(c.preview ? 'Keluar dari pratinjau' : 'Keluar'),
          ),
        ),
      ],
    );
  }

  Future<void> _profile(BuildContext context) async {
    final name = TextEditingController(text: controller.me!.name),
        bio = TextEditingController(text: controller.me!.bio);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Nama tampilan'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: bio,
                maxLength: 160,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Tentangmu'),
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
              if (name.text.trim().isNotEmpty) Navigator.pop(context, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await controller.updateProfile(name.text, bio.text);
      } catch (_) {
        if (context.mounted) {
          showNotice(context, 'Profil belum tersimpan. Coba lagi.');
        }
      }
    }
    name.dispose();
    bio.dispose();
  }

  void _appearance(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionLabel('Tampilan'),
            for (final mode in ThemeMode.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(switch (mode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                }),
                title: Text(switch (mode) {
                  ThemeMode.system => 'Ikuti sistem',
                  ThemeMode.dark => 'Midnight Blue',
                  ThemeMode.light => 'Ice Blue',
                }),
                trailing: controller.theme == mode
                    ? const Icon(Icons.check_circle_rounded, color: ice)
                    : null,
                onTap: () {
                  controller.setTheme(mode);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
