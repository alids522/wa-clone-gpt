import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_runtime/device_runtime.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../core/push_service.dart';
import '../core/controller.dart';
import '../app/widgets.dart';

class NotificationSettings extends StatelessWidget {
  const NotificationSettings({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifikasi')),
    body: ValueListenableBuilder<PushState>(
      valueListenable: PushService.status,
      builder: (context, state, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(
            state == PushState.ready
                ? Icons.notifications_active_outlined
                : Icons.notifications_outlined,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            PushService.explanation,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Isi pesan disembunyikan pada notifikasi. Panggilan memakai izin notifikasi dan pengaturan layar kunci perangkat.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: state == PushState.checking
                ? null
                : () => PushService.enable(controller),
            icon: const Icon(Icons.refresh),
            label: Text(
              state == PushState.checking
                  ? 'Menyiapkan…'
                  : 'Aktifkan / coba lagi',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) {
                  await FlutterCallkitIncoming.requestFullIntentPermission();
                }
              } catch (_) {
                if (context.mounted) {
                  showNotice(
                    context,
                    'Pengaturan layar panggilan belum tersedia pada perangkat ini.',
                  );
                }
              }
            },
            icon: const Icon(Icons.phone_locked),
            label: const Text('Layar panggilan masuk'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: DeviceRuntime.openNotificationSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Pengaturan Android'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await PushService.testNotification();
                if (context.mounted) {
                  showNotice(
                    context,
                    'Tes notifikasi lokal dikirim. Tes ini memeriksa tampilan di perangkat.',
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  showNotice(
                    context,
                    'Tes lokal gagal. Periksa izin dan channel Pesan di pengaturan Android.',
                  );
                }
              }
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Tes notifikasi perangkat'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Status aktif berarti token Firebase sudah terdaftar ke server dan izin notifikasi Android diberikan. Uji pesan dari perangkat lain untuk memeriksa push saat layar mati.',
            style: TextStyle(fontSize: 12),
          ),
          if (PushService.diagnosticCode.isNotEmpty)
            TextButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text:
                      'adoetz-push/${state.name}/${PushService.diagnosticCode}',
                ),
              ),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Salin kode diagnostik'),
            ),
        ],
      ),
    ),
  );
}
