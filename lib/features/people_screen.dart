import 'dart:async';
import 'package:flutter/material.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'chat_screen.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  Timer? debounce;
  List<Person> people = [];
  bool loading = false, searched = false;
  String? error;
  int request = 0;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  void search(String s) {
    debounce?.cancel();
    final token = ++request;
    if (s.trim().length < 3) {
      setState(() {
        people = [];
        searched = false;
        loading = false;
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final result = await widget.controller.searchPeople(s);
        if (mounted && token == request) {
          setState(() {
            people = result;
            searched = true;
          });
        }
      } catch (_) {
        if (mounted && token == request) {
          setState(
            () => error =
                'Pencarian belum tersedia. Periksa koneksi lalu coba lagi.',
          );
        }
      } finally {
        if (mounted && token == request) setState(() => loading = false);
      }
    });
  }

  Future<void> open(Person p) async {
    try {
      final chat = await widget.controller.startChat(p);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(controller: widget.controller, chat: chat),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        showNotice(context, 'Percakapan belum dapat dibuat. Coba lagi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: TextField(
          onChanged: search,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Cari username teman',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Ketik minimal 3 karakter username.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: error != null
            ? EmptyState(
                icon: Icons.wifi_off,
                title: 'Belum dapat mencari',
                body: error!,
              )
            : people.isEmpty
            ? EmptyState(
                icon: Icons.person_search_outlined,
                title: searched
                    ? 'Username tidak ditemukan'
                    : 'Temukan orang terdekat',
                body: searched
                    ? 'Periksa ejaan username dan coba lagi.'
                    : 'Tanpa sinkronisasi buku telepon.\nCukup cari username untuk mulai mengobrol.',
              )
            : ListView(
                children: [
                  const SectionLabel('Hasil pencarian'),
                  for (final p in people)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      leading: Avatar(p),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('@${p.username}'),
                      trailing: const Icon(Icons.chat_bubble_outline_rounded),
                      onTap: () => open(p),
                    ),
                ],
              ),
      ),
    ],
  );
}
