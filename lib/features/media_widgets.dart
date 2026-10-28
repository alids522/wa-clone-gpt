import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../app/widgets.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/media_service.dart';

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
  bool loading = false;
  AudioPlayer? player;
  File? file;
  Future<void> open() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      file ??= await MediaService.download(widget.controller, widget.message);
      if (!mounted) return;
      if (widget.message.kind == 'voice') {
        player ??= AudioPlayer();
        if (player!.playing) {
          await player!.pause();
        } else {
          await player!.setFilePath(file!.path);
          unawaited(player!.play());
        }
      } else if ((widget.message.data['mime'] as String? ?? '').startsWith(
        'image/',
      )) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: InteractiveViewer(
              child: Image.file(
                file!,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Format gambar tidak didukung.'),
                ),
              ),
            ),
          ),
        );
      } else {
        await OpenFilex.open(file!.path);
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Lampiran belum dapat dibuka. Periksa koneksi dan coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    player?.dispose();
    if (widget.message.kind == 'voice') {
      file?.delete().catchError((Object _) => file!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: open,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              widget.message.kind == 'voice'
                  ? Icons.play_circle_outline
                  : Icons.download_outlined,
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.kind == 'voice'
                      ? 'Pesan suara'
                      : widget.message.data['name'] ?? 'Lampiran',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${((widget.message.data['size'] as num? ?? 0) / 1024).round()} KB${widget.message.data['duration'] != null ? ' · ${((widget.message.data['duration'] as num) / 1000).round()} dtk' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
