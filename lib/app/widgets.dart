import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/models.dart';
import 'theme.dart';

class Avatar extends StatelessWidget {
  const Avatar(this.person, {super.key, this.radius = 26});
  final Person person;
  final double radius;
  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF0D9488),
      Color(0xFFEA580C),
      Color(0xFFDB2777),
    ];
    final color =
        colors[person.username.codeUnits.fold(0, (a, b) => a + b) %
            colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: .2),
      child: person.avatarPath != null
          ? _AvatarPhoto(path: person.avatarPath!, radius: radius)
          : Text(
              person.name.isEmpty
                  ? '?'
                  : person.name.characters.first.toUpperCase(),
              style: TextStyle(
                color: color.computeLuminance() < .15 ? ice : color,
                fontSize: radius * .72,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _AvatarPhoto extends StatefulWidget {
  const _AvatarPhoto({required this.path, required this.radius});
  final String path;
  final double radius;
  @override
  State<_AvatarPhoto> createState() => _AvatarPhotoState();
}

class _AvatarPhotoState extends State<_AvatarPhoto> {
  late Future<Uint8List> photo;
  Future<Uint8List> load() async =>
      Supabase.instance.client.storage.from('avatars').download(widget.path);
  @override
  void initState() {
    super.initState();
    photo = load();
  }

  @override
  void didUpdateWidget(covariant _AvatarPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) photo = load();
  }

  @override
  Widget build(BuildContext context) => ClipOval(
    child: FutureBuilder<Uint8List>(
      future: photo,
      builder: (context, snapshot) => snapshot.hasData
          ? Image.memory(
              snapshot.data!,
              width: widget.radius * 2,
              height: widget.radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.person),
            )
          : const Icon(Icons.person),
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 76});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF397BFF), Color(0xFF1642A6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(size * .30),
      boxShadow: [
        BoxShadow(
          color: brand.withValues(alpha: .24),
          blurRadius: 32,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Icon(Icons.forum_rounded, size: size * .47, color: Colors.white),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: brand.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: ice, size: 38),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 26, 24, 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

void showNotice(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    ) ??
    false;
