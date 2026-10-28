import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_runtime/device_runtime.dart';
import 'package:path_provider/path_provider.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/media_service.dart';
import '../app/widgets.dart';
import 'media_widgets.dart';

class PickedAttachment {
  PickedAttachment(this.file, this.name, {this.document = false});
  final File file;
  final String name;
  final bool document;
}

Future<void> composeAttachments(
  BuildContext context,
  ChatController controller,
  Conversation chat,
) async {
  if (controller.preview) {
    showNotice(context, 'Lampiran tersedia setelah masuk.');
    return;
  }
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kirim lampiran',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final option in <(String, String, IconData)>[
                  ('photos', 'Foto', Icons.photo_outlined),
                  ('videos', 'Video', Icons.video_library_outlined),
                  ('camera', 'Kamera', Icons.photo_camera_outlined),
                  ('record', 'Rekam video', Icons.videocam_outlined),
                  ('documents', 'Dokumen', Icons.insert_drive_file_outlined),
                ])
                  SizedBox(
                    width: 94,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, option.$1),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 24, child: Icon(option.$3)),
                          const SizedBox(height: 6),
                          Text(option.$2, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  final picker = ImagePicker();
  final items = <PickedAttachment>[];
  try {
    if (kind == 'photos') {
      for (final file in await picker.pickMultiImage(
        limit: 10,
        requestFullMetadata: false,
      )) {
        items.add(PickedAttachment(File(file.path), file.name));
      }
    } else if (kind == 'videos') {
      for (final file in await FilePicker.pickFiles(type: FileType.video)) {
        if (file.path != null) {
          items.add(PickedAttachment(File(file.path!), file.name));
        }
      }
    } else if (kind == 'documents') {
      for (final file in await FilePicker.pickFiles()) {
        if (file.path != null) {
          items.add(
            PickedAttachment(File(file.path!), file.name, document: true),
          );
        }
      }
    } else {
      final file = kind == 'camera'
          ? await picker.pickImage(source: ImageSource.camera)
          : await picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 10),
            );
      if (file != null) items.add(PickedAttachment(File(file.path), file.name));
    }
    if (items.isEmpty || !context.mounted) return;
    if (items.length > 10) {
      throw StateError('Pilih maksimal 10 file dalam satu pengiriman.');
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AttachmentComposer(
          controller: controller,
          chat: chat,
          items: items,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      showNotice(
        context,
        e is StateError
            ? e.message
            : 'File belum dapat dipilih. Periksa izin kamera dan coba lagi.',
      );
    }
  }
}

class AttachmentComposer extends StatefulWidget {
  const AttachmentComposer({
    super.key,
    required this.controller,
    required this.chat,
    required this.items,
  });
  final ChatController controller;
  final Conversation chat;
  final List<PickedAttachment> items;
  @override
  State<AttachmentComposer> createState() => _AttachmentComposerState();
}

class _AttachmentComposerState extends State<AttachmentComposer> {
  final caption = TextEditingController();
  late final items = List<PickedAttachment>.from(widget.items);
  int selected = 0;
  bool sending = false;
  String? error;
  final previews = <String, Future<Map<String, dynamic>>>{};
  Future<Map<String, dynamic>> preview(PickedAttachment item) =>
      previews.putIfAbsent(item.file.path, () async {
        final mime = await MediaService.mimeFor(item.file, item.name);
        final metadata = item.document
            ? <String, dynamic>{}
            : await DeviceRuntime.mediaPreview(
                item.file.path,
                mime,
              ).catchError((Object _) => <String, dynamic>{});
        return {...metadata, 'mime': mime, 'size': await item.file.length()};
      });
  Future<void> send() async {
    setState(() => sending = true);
    try {
      // Remove only after durable enqueue. A later failure retries remaining files.
      while (items.isNotEmpty) {
        final item = items.first;
        await MediaService.send(
          widget.controller,
          widget.chat,
          item.file,
          item.name,
          caption: caption.text,
          asDocument: item.document,
        );
        if (!mounted) return;
        setState(() {
          items.removeAt(0);
          selected = 0;
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Belum dapat menyimpan antrean lampiran. Coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    caption.dispose();
    _clearPickedCopies();
    super.dispose();
  }

  Future<void> _clearPickedCopies() async {
    final cache =
        (await getTemporaryDirectory()).absolute.path + Platform.pathSeparator;
    for (final item in widget.items) {
      try {
        if (item.file.absolute.path.startsWith(cache) &&
            await item.file.exists()) {
          await item.file.delete();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Kirim ke ${widget.chat.peer.name}',
          style: const TextStyle(fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : FutureBuilder<Map<String, dynamic>>(
                      future: preview(items[selected]),
                      builder: (context, snapshot) {
                        final data = snapshot.data, item = items[selected];
                        if (data == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final mime = data['mime'] as String;
                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!item.document && mime.startsWith('image/'))
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.sizeOf(context).height *
                                          .45,
                                    ),
                                    child: Image.file(
                                      item.file,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image_outlined,
                                        size: 64,
                                      ),
                                    ),
                                  )
                                else if (!item.document &&
                                    data['thumbnail'] != null)
                                  AttachmentPreviewImage(
                                    base64: data['thumbnail'],
                                  )
                                else
                                  Icon(
                                    mime.startsWith('video/')
                                        ? Icons.movie_outlined
                                        : Icons.description_outlined,
                                    size: 80,
                                  ),
                                const SizedBox(height: 12),
                                Text(item.name, textAlign: TextAlign.center),
                                Text(
                                  '${((data['size'] as num) / 1048576).toStringAsFixed(1)} MB · ${mime.split('/').last.toUpperCase()}',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (items.length > 1)
              SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(
                        '${i + 1}. ${items[i].name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: selected == i,
                      onSelected: sending
                          ? null
                          : (_) => setState(() => selected = i),
                    ),
                  ),
                ),
              ),
            if (error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: caption,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 3,
                      enabled: !sending,
                      decoration: const InputDecoration(
                        hintText: 'Tambahkan caption…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Kirim lampiran',
                    onPressed: sending ? null : send,
                    icon: Icon(sending ? Icons.hourglass_top : Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
