import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:device_runtime/device_runtime.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/media_service.dart';
import 'media_viewer.dart';

class AttachmentPreviewImage extends StatelessWidget {
  const AttachmentPreviewImage({
    super.key,
    required this.base64,
    this.height = 190,
  });
  final String base64;
  final double height;
  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      if (base64.length <= 22000) bytes = base64Decode(base64);
    } catch (_) {}
    return bytes == null
        ? const Icon(Icons.image_outlined, size: 48)
        : Image.memory(
            bytes,
            height: height,
            width: 270,
            fit: BoxFit.cover,
            cacheWidth: 360,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, size: 48),
          );
  }
}

class AttachmentBubble extends StatefulWidget {
  const AttachmentBubble({
    super.key,
    required this.controller,
    required this.message,
  });
  final ChatController controller;
  final ChatMessage message;
  @override
  State<AttachmentBubble> createState() => _AttachmentBubbleState();
}

class _AttachmentBubbleState extends State<AttachmentBubble> {
  File? file;
  AudioPlayer? player;
  Future<File>? _loading;
  MediaDownload? transfer;
  bool busy = false, saving = false, audioReady = false, viewing = false;
  double progress = 0, speed = 1;
  String? error;
  ChatMessage get message => widget.message;
  String get mime =>
      message.data['mime'] as String? ?? 'application/octet-stream';
  String get kind => message.kind == 'voice'
      ? 'voice'
      : message.data['presentation'] as String? ??
            (mime.startsWith('image/')
                ? 'image'
                : mime.startsWith('video/')
                ? 'video'
                : 'document');
  bool get pending => message.data['_upload_path'] != null;
  @override
  void initState() {
    super.initState();
    if (kind == 'voice') player = AudioPlayer();
    _oldImage();
  }

  @override
  void didUpdateWidget(covariant AttachmentBubble old) {
    super.didUpdateWidget(old);
    _oldImage();
  }

  void _oldImage() {
    if (kind == 'image' &&
        message.data['thumbnail'] == null &&
        !pending &&
        message.delivery != Delivery.queued &&
        file == null &&
        _loading == null &&
        !widget.controller.preview &&
        error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSilently();
      });
    }
  }

  Future<void> _loadSilently() async {
    try {
      await ensureFile();
    } catch (_) {}
  }

  Future<File> ensureFile() {
    if (file != null) return Future.value(file);
    return _loading ??= _download().whenComplete(() => _loading = null);
  }

  Future<File> _download() async {
    if (pending) throw StateError('Lampiran masih diunggah.');
    setState(() {
      busy = true;
      progress = 0;
      error = null;
    });
    final operation = MediaDownload();
    transfer = operation;
    try {
      final received = await MediaService.download(
        widget.controller,
        message,
        transfer: operation,
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (!mounted) {
        await received.delete();
        throw StateError('Viewer closed');
      }
      setState(() => file = received);
      return received;
    } catch (e) {
      if (mounted && !operation.cancelled) {
        setState(() => error = 'Unduhan gagal. Ketuk untuk coba lagi.');
      }
      rethrow;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open() async {
    if (busy || pending) return;
    try {
      final local = await ensureFile();
      if (!mounted) return;
      if (kind == 'voice') {
        if (player!.playing) {
          await player!.pause();
        } else {
          if (!audioReady) {
            await player!.setFilePath(local.path);
            audioReady = true;
          }
          if (player!.processingState == ProcessingState.completed) {
            await player!.seek(Duration.zero);
          }
          unawaited(player!.play());
        }
        if (mounted) setState(() {});
      } else if (kind == 'image' || kind == 'video') {
        viewing = true;
        try {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => MediaViewer(
                file: local,
                name: message.data['name'] ?? 'Media',
                mime: mime,
                caption: message.data['caption'] ?? '',
              ),
            ),
          );
        } finally {
          viewing = false;
          if (!mounted) await _deleteFile();
        }
      } else {
        final result = await OpenFilex.open(local.path);
        if (result.type != ResultType.done && mounted) {
          showNotice(
            context,
            'Tidak ada aplikasi yang dapat membuka file ini. Gunakan Simpan untuk menyimpannya.',
          );
        }
      }
    } catch (_) {
      if (mounted && !(transfer?.cancelled ?? false)) {
        showNotice(context, 'Lampiran belum dapat dibuka. Coba lagi.');
      }
    }
  }

  Future<void> save({bool choose = false}) async {
    if (saving || pending) return;
    setState(() => saving = true);
    try {
      final local = await ensureFile();
      final result = await DeviceRuntime.saveFile(
        local.path,
        message.data['name'] ?? 'Lampiran',
        mime,
        chooseLocation: choose,
      );
      if (result != null && mounted) {
        showNotice(
          context,
          (kind == 'image' || kind == 'video')
              ? 'Disimpan ke Galeri · Adoetz Chat'
              : 'File disimpan ke ${choose ? 'lokasi pilihan' : 'Download/Adoetz Chat'}',
        );
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'File belum dapat disimpan. Periksa ruang penyimpanan lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _deleteFile() async {
    try {
      if (file != null && await file!.exists()) await file!.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    transfer?.cancel();
    player?.dispose().whenComplete(_deleteFile);
    if (player == null && !viewing) _deleteFile();
    super.dispose();
  }

  Widget preview() => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (file != null && kind == 'image')
          Image.file(
            file!,
            width: 270,
            height: 190,
            fit: BoxFit.cover,
            cacheWidth: 540,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 250,
              height: 150,
              child: Icon(Icons.broken_image_outlined, size: 48),
            ),
          )
        else if (message.data['thumbnail'] is String)
          AttachmentPreviewImage(base64: message.data['thumbnail'])
        else
          Container(
            width: 250,
            height: 150,
            color: Colors.black12,
            child: Icon(
              kind == 'video' ? Icons.videocam_outlined : Icons.image_outlined,
              size: 48,
            ),
          ),
        if (kind == 'video')
          const CircleAvatar(
            backgroundColor: Colors.black54,
            child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
          ),
        if (kind == 'video' && message.data['duration'] is num)
          Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              clock(
                Duration(
                  milliseconds: (message.data['duration'] as num).toInt(),
                ),
              ),
              style: const TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        if (!pending &&
            message.delivery != Delivery.queued &&
            message.delivery != Delivery.failed)
          Positioned(
            right: 4,
            top: 4,
            child: IconButton.filledTonal(
              tooltip: 'Simpan ke Galeri',
              onPressed: saving ? null : save,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                saving ? Icons.hourglass_top : Icons.save_alt,
                size: 19,
              ),
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final caption = message.data['caption'] as String? ?? '';
    final upload = widget.controller.uploadProgress[message.id];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: busy || pending ? null : open,
            borderRadius: BorderRadius.circular(10),
            child: kind == 'image' || kind == 'video'
                ? preview()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (kind == 'voice')
                          StreamBuilder<PlayerState>(
                            stream: player!.playerStateStream,
                            builder: (context, snapshot) => Icon(
                              snapshot.data?.playing == true &&
                                      snapshot.data?.processingState !=
                                          ProcessingState.completed
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              size: 34,
                            ),
                          )
                        else
                          const Icon(Icons.description_outlined, size: 32),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kind == 'voice'
                                    ? 'Pesan suara'
                                    : message.data['name'] ?? 'Dokumen',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${((message.data['size'] as num? ?? 0) / 1024).round()} KB · ${mime.split('/').last.toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (kind == 'document' &&
                            !pending &&
                            message.delivery != Delivery.queued &&
                            message.delivery != Delivery.failed)
                          IconButton(
                            tooltip: 'Simpan ke Download',
                            onPressed: saving ? null : save,
                            icon: Icon(
                              saving ? Icons.hourglass_top : Icons.save_alt,
                              size: 19,
                            ),
                          ),
                        if (kind == 'document' && !pending)
                          PopupMenuButton<String>(
                            tooltip: 'Lokasi penyimpanan',
                            icon: const Icon(Icons.more_vert, size: 18),
                            onSelected: (_) => save(choose: true),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'save-as',
                                child: Text('Simpan sebagai…'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(caption),
            ),
          if (error != null) Text(error!, style: const TextStyle(fontSize: 11)),
          if (busy || pending)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: pending
                            ? upload
                            : progress == 0
                            ? null
                            : progress,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pending
                            ? (upload == null
                                  ? 'Menunggu upload…'
                                  : 'Mengunggah ${(upload * 100).round()}%')
                            : progress >= 1
                            ? 'Memverifikasi file…'
                            : 'Mengunduh ${(progress * 100).round()}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Batalkan transfer',
                  onPressed: () => pending
                      ? widget.controller.cancelAttachment(message.id)
                      : transfer?.cancel(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            )
          else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                if (kind == 'voice' && audioReady)
                  TextButton(
                    onPressed: () async {
                      speed = speed == 1
                          ? 1.5
                          : speed == 1.5
                          ? 2
                          : 1;
                      await player!.setSpeed(speed);
                      if (mounted) setState(() {});
                    },
                    child: Text('${speed}x'),
                  ),
                if (message.delivery == Delivery.failed)
                  TextButton.icon(
                    onPressed: () => widget.controller.retryMessage(message.id),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Coba lagi'),
                  ),
                if (kind == 'voice' &&
                    message.delivery != Delivery.queued &&
                    message.delivery != Delivery.failed)
                  IconButton(
                    tooltip: kind == 'image' || kind == 'video'
                        ? 'Simpan ke Galeri'
                        : 'Simpan ke Download',
                    onPressed: saving ? null : save,
                    icon: Icon(
                      saving ? Icons.hourglass_top : Icons.save_alt,
                      size: 19,
                    ),
                  ),
              ],
            ),
          if (kind == 'voice' && audioReady)
            StreamBuilder<Duration>(
              stream: player!.positionStream,
              builder: (context, snapshot) {
                final max = (player!.duration?.inMilliseconds.toDouble() ?? 1)
                    .clamp(1.0, double.infinity);
                return Slider(
                  max: max,
                  value: (snapshot.data?.inMilliseconds.toDouble() ?? 0).clamp(
                    0,
                    max,
                  ),
                  semanticFormatterCallback: (v) =>
                      '${(v / 1000).round()} detik',
                  onChanged: (v) =>
                      player!.seek(Duration(milliseconds: v.round())),
                );
              },
            ),
        ],
      ),
    );
  }
}

class VoiceRecorderSheet extends StatefulWidget {
  const VoiceRecorderSheet({
    super.key,
    required this.controller,
    required this.chat,
  });
  final ChatController controller;
  final Conversation chat;
  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> {
  final recorder = AudioRecorder(), player = AudioPlayer();
  Timer? timer;
  File? file;
  int seconds = 0;
  bool recording = false, sending = false;
  String? error;
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      if (!await recorder.hasPermission()) {
        throw StateError(
          'Izinkan mikrofon di pengaturan perangkat untuk merekam.',
        );
      }
      final dir = await getTemporaryDirectory();
      file = File(
        '${dir.path}/adoetz-voice-${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 24000,
        ),
        path: file!.path,
      );
      if (!mounted) {
        await recorder.cancel();
        return;
      }
      setState(() => recording = true);
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => seconds++);
        if (seconds >= 600) stop();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Tidak dapat membuka mikrofon.',
        );
      }
    }
  }

  Future<void> stop() async {
    timer?.cancel();
    await recorder.stop();
    if (mounted) setState(() => recording = false);
  }

  Future<void> send() async {
    if (file == null || sending || seconds == 0) return;
    setState(() => sending = true);
    try {
      if (recording) await stop();
      await player.stop();
      await MediaService.send(
        widget.controller,
        widget.chat,
        file!,
        'voice-note.m4a',
        voice: true,
        duration: seconds * 1000,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          sending = false;
          error = 'Pesan suara belum terkirim. Coba lagi.';
        });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    recorder.dispose().whenComplete(() async {
      if (file != null && await file!.exists()) await file!.delete();
    });
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            recording ? Icons.mic : Icons.graphic_eq,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 32),
          ),
          const Text('Maksimal 10 menit'),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              if (recording)
                OutlinedButton(onPressed: stop, child: const Text('Berhenti'))
              else if (file != null)
                OutlinedButton(
                  onPressed: () async {
                    await player.setFilePath(file!.path);
                    unawaited(player.play());
                  },
                  child: const Text('Dengarkan'),
                ),
              FilledButton(
                onPressed: sending || seconds == 0 ? null : send,
                child: Text(sending ? 'Mengirim…' : 'Kirim'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
