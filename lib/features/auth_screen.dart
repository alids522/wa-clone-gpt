import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool form = false, register = false, hidden = true, consent = false;
  final _key = GlobalKey<FormState>();
  final identifier = TextEditingController(),
      password = TextEditingController(),
      username = TextEditingController(),
      invite = TextEditingController(),
      confirm = TextEditingController();
  @override
  void dispose() {
    for (final c in [identifier, password, username, invite, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!_key.currentState!.validate() || (register && !consent)) return;
    FocusScope.of(context).unfocus();
    await widget.controller.authenticate(
      identifier: identifier.text,
      password: password.text,
      username: register ? username.text : null,
      invite: register ? invite.text : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              children: [
                Row(
                  children: [
                    if (form)
                      IconButton(
                        onPressed: c.busy
                            ? null
                            : () => setState(() => form = false),
                        tooltip: 'Kembali',
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Ganti tema',
                      onPressed: () => c.setTheme(
                        Theme.of(context).brightness == Brightness.dark
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      ),
                      icon: const Icon(Icons.brightness_6_outlined),
                    ),
                  ],
                ),
                SizedBox(height: form ? 28 : 64),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BrandMark(size: form ? 60 : 88),
                ),
                const SizedBox(height: 30),
                Text(
                  form
                      ? (register
                            ? 'Ruang baru,\nkoneksi baru.'
                            : 'Senang kamu\nkembali.')
                      : 'Percakapan kecil.\nKoneksi berarti.',
                  style: const TextStyle(
                    fontSize: 38,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.6,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  form
                      ? (register
                            ? 'Buat akun Adoetz Chat dengan kode undanganmu.'
                            : 'Masuk untuk melanjutkan percakapanmu.')
                      : 'Pesan privat, tetap simpel.\nTempat untuk orang-orang terdekatmu.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.65,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 36),
                if (!form) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.mark_chat_unread_outlined, color: ice),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hanya melalui undangan',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Komunitas privat. Tanpa nomor telepon.',
                                style: TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => setState(() {
                      form = true;
                      register = false;
                    }),
                    child: const Text('Masuk'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      form = true;
                      register = true;
                    }),
                    child: const Text('Punya undangan? Buat akun'),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: c.openPreview,
                    child: const Text('Jelajahi pratinjau aplikasi →'),
                  ),
                ] else
                  Form(
                    key: _key,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (register) ...[
                            TextFormField(
                              controller: invite,
                              decoration: const InputDecoration(
                                labelText: 'Kode undangan',
                                prefixIcon: Icon(Icons.key_outlined),
                              ),
                              validator: (v) => (v?.trim().isEmpty ?? true)
                                  ? 'Masukkan kode undangan.'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: username,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixText: '@',
                              ),
                              validator: validateUsername,
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: identifier,
                            keyboardType: register
                                ? TextInputType.emailAddress
                                : TextInputType.text,
                            autofillHints: register
                                ? [AutofillHints.email]
                                : [AutofillHints.username],
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: register
                                  ? 'Email'
                                  : 'Email atau username',
                              prefixIcon: const Icon(Icons.alternate_email),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Isi email atau username.';
                              }
                              if (register &&
                                  !RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(v.trim())) {
                                return 'Masukkan email yang valid.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: password,
                            obscureText: hidden,
                            autofillHints: [
                              register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: hidden
                                    ? 'Tampilkan password'
                                    : 'Sembunyikan password',
                                onPressed: () =>
                                    setState(() => hidden = !hidden),
                                icon: Icon(
                                  hidden
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: register
                                ? validatePassword
                                : (v) => v?.isEmpty ?? true
                                      ? 'Masukkan password.'
                                      : null,
                            onFieldSubmitted: (_) {
                              if (!register && !c.busy) submit();
                            },
                          ),
                          if (register) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: confirm,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Konfirmasi password',
                              ),
                              validator: (v) => v != password.text
                                  ? 'Password belum sama.'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: consent,
                              onChanged: (v) => setState(() => consent = v!),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'Saya memahami pemberitahuan privasi prototipe.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            const Text(
                              'Email belum diverifikasi. Pemulihan riwayat tanpa kunci perangkat tidak tersedia.',
                              style: TextStyle(fontSize: 12, height: 1.6),
                            ),
                          ],
                          if (!c.configured) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Koneksi akun sedang disiapkan. Kamu dapat menjelajahi pratinjau terlebih dahulu.',
                              style: TextStyle(color: ice, height: 1.5),
                            ),
                          ],
                          if (c.error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              c.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                height: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed:
                                c.busy ||
                                    !c.configured ||
                                    (register && !consent)
                                ? null
                                : submit,
                            child: c.busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(register ? 'Buat akun' : 'Masuk'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: c.busy
                                ? null
                                : () => setState(() {
                                    register = !register;
                                    c.error = null;
                                  }),
                            child: Text(
                              register
                                  ? 'Sudah punya akun? Masuk'
                                  : 'Buat akun dengan undangan',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 34),
                Center(
                  child: Text(
                    'ADOETZ CHAT  /  0.1.0 ALPHA',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2.3,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'Prototipe internal • belum diaudit keamanannya',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: ice),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
