import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:device_runtime/device_runtime.dart';
import '../app/widgets.dart';

class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.file,
    required this.name,
    required this.mime,
    this.caption = '',
  });
  final File file;
  final String name, mime, caption;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> with WidgetsBindingObserver {
  VideoPlayerController? video;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.mime.startsWith('video/')) {
      video = VideoPlayerController.file(widget.file);
      video!
          .initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object _) {
            if (mounted) {
              setState(
                () => error =
                    'Video belum dapat diputar pada perangkat ini. File tetap dapat disimpan.',
              );
            }
          });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) video?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    video?.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await DeviceRuntime.saveFile(widget.file.path, widget.name, widget.mime);
      if (mounted) showNotice(context, 'Disimpan ke Galeri · Adoetz Chat');
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Media belum dapat disimpan. Periksa ruang penyimpanan.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080D18),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      title: Text(widget.name, style: const TextStyle(fontSize: 15)),
      actions: [
        IconButton(
          tooltip: 'Simpan ke Galeri',
          onPressed: saving ? null : save,
          icon: Icon(saving ? Icons.hourglass_top : Icons.save_alt),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: video == null
                  ? InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Image.file(
                        widget.file,
                        errorBuilder: (_, _, _) => const Text(
                          'Format foto belum dapat dibuka.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                  : error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : !video!.value.isInitialized
                  ? const CircularProgressIndicator()
                  : AspectRatio(
                      aspectRatio: video!.value.aspectRatio,
                      child: VideoPlayer(video!),
                    ),
            ),
          ),
          if (video != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: video!,
              builder: (context, value, _) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      video!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF60A5FA),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: value.isPlaying ? 'Jeda' : 'Putar video',
                          onPressed: !value.isInitialized
                              ? null
                              : () async {
                                  if (value.isPlaying) {
                                    await video!.pause();
                                  } else {
                                    if (value.position >= value.duration) {
                                      await video!.seekTo(Duration.zero);
                                    }
                                    await video!.play();
                                  }
                                },
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${clock(value.position)} / ${clock(value.duration)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        IconButton(
                          tooltip: value.volume == 0
                              ? 'Aktifkan suara'
                              : 'Bisukan video',
                          onPressed: () =>
                              video!.setVolume(value.volume == 0 ? 1 : 0),
                          icon: Icon(
                            value.volume == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (widget.caption.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  widget.caption,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

String clock(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
