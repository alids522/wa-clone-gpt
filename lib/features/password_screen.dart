import 'package:flutter/material.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({
    super.key,
    required this.controller,
    this.forced = false,
  });
  final ChatController controller;
  final bool forced;
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final form = GlobalKey<FormState>();
  final oldPassword = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false;
  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() => busy = true);
    try {
      await widget.controller.changePassword(
        password.text,
        currentPassword: widget.forced ? null : oldPassword.text,
      );
      if (mounted && !widget.forced) {
        showNotice(
          context,
          'Password diganti. Perangkat lain perlu masuk kembali.',
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Password belum dapat diganti. Periksa password saat ini dan koneksi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    oldPassword.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ganti password'),
      automaticallyImplyLeading: !widget.forced,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.forced
                    ? 'Buat password pribadi untuk mengganti password sementara dari administrator.'
                    : 'Perubahan password membatalkan sesi perangkat lain. Kunci dan riwayat lokal tetap disimpan.',
              ),
              const SizedBox(height: 24),
              if (!widget.forced) ...[
                TextFormField(
                  controller: oldPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password saat ini',
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Masukkan password saat ini.'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password baru'),
                validator: validatePassword,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Ulangi password baru',
                ),
                validator: (v) =>
                    v != password.text ? 'Password tidak sama.' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Menyimpan…' : 'Simpan password'),
              ),
              if (widget.forced)
                TextButton(
                  onPressed: busy ? null : widget.controller.logout,
                  child: const Text('Keluar'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
