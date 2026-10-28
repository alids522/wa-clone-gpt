import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<dynamic>? devices;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.controller.client!.rpc(
        'device_settings',
        params: {'device': widget.controller.deviceId, 'operation': 'list'},
      );
      if (mounted) setState(() => devices = result);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Daftar perangkat belum dapat dimuat.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Perangkat & kunci')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Akun yang sama dapat dipakai di beberapa perangkat. Tiap perangkat memiliki kunci sendiri dan menerima pesan baru. Riwayat lama tetap berada di perangkat yang memiliki kuncinya.',
          ),
        ),
        if (error != null)
          ListTile(
            title: Text(error!),
            trailing: IconButton(
              onPressed: load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        if (devices == null && error == null)
          const Center(child: CircularProgressIndicator()),
        for (final device in devices ?? [])
          ListTile(
            leading: Icon(
              device['revoked_at'] != null
                  ? Icons.phonelink_erase
                  : Icons.devices,
            ),
            title: Text(
              '${device['label']}${device['id'] == widget.controller.deviceId ? ' · perangkat ini' : ''}',
            ),
            subtitle: Text(
              device['revoked_at'] != null
                  ? 'Akses dicabut'
                  : '${device['id']}\nAktif: ${DateTime.parse(device['last_seen']).toLocal().toString().substring(0, 16)}',
            ),
            trailing:
                device['revoked_at'] == null &&
                    device['id'] != widget.controller.deviceId
                ? IconButton(
                    tooltip: 'Cabut akses',
                    icon: const Icon(Icons.logout),
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        'Cabut akses perangkat?',
                        'Perangkat ini berhenti menerima pesan baru dan sesinya dibatalkan. Pesan yang sudah tersimpan di sana tetap bisa dibaca secara lokal.',
                      )) {
                        try {
                          await widget.controller.client!.rpc(
                            'device_settings',
                            params: {
                              'device': device['id'],
                              'operation': 'revoke',
                            },
                          );
                          await load();
                        } catch (_) {
                          if (context.mounted) {
                            showNotice(context, 'Akses belum dapat dicabut.');
                          }
                        }
                      }
                    },
                  )
                : null,
          ),
      ],
    ),
  );
}

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key, required this.controller, required this.chat});
  final ChatController controller;
  final Conversation chat;
  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  String? number, error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final c = widget.controller;
      final devices =
          await c.client!.rpc('chat_devices', params: {'chat': widget.chat.id})
              as List;
      final own = <IdentityKey>[], peer = <IdentityKey>[];
      for (final device in devices) {
        final identity = IdentityKey.fromBytes(
          base64Decode(device['identity_key']),
          0,
        );
        (device['user_id'] == c.me!.id ? own : peer).add(identity);
      }
      final fingerprint = NumericFingerprintGenerator(5200)
          .createListFor(
            1,
            Uint8List.fromList(utf8.encode(c.me!.id)),
            own,
            Uint8List.fromList(utf8.encode(widget.chat.peer.id)),
            peer,
          )
          .displayableFingerprint
          .getDisplayText();
      final formatted = RegExp(
        '.{1,5}',
      ).allMatches(fingerprint).map((m) => m.group(0)).join(' ');
      if (mounted) setState(() => number = formatted);
    } catch (_) {
      if (mounted) setState(() => error = 'Nomor keamanan belum dapat dimuat.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verifikasi keamanan')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.chat.peer.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          const Text(
            'Bandingkan seluruh angka ini dengan kontakmu melalui pertemuan langsung atau kanal lain yang kamu percaya. Nomor mencakup seluruh perangkat aktif kedua akun dan berubah saat perangkat ditambah atau dicabut.',
          ),
          const SizedBox(height: 28),
          if (number != null)
            SelectableText(
              number!,
              style: const TextStyle(
                fontSize: 25,
                height: 1.6,
                letterSpacing: 2,
              ),
            )
          else if (error != null)
            Text(error!)
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Perbarui nomor'),
          ),
        ],
      ),
    ),
  );
}
