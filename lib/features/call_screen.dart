import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app/widgets.dart';
import '../core/call_service.dart';
import '../core/models.dart';
import 'media_viewer.dart' show clock;

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.service});
  final CallService service;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? timer;
  Duration elapsed = Duration.zero;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.service.connectedAt != null) {
        setState(
          () =>
              elapsed = DateTime.now().difference(widget.service.connectedAt!),
        );
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final c = widget.service;
      return CallView(
        peer:
            c.chat?.peer ??
            const Person(id: 'call', username: 'call', name: 'Adoetz Chat'),
        state: c.state,
        video: c.video,
        incoming: c.incoming,
        active: c.active,
        muted: c.muted,
        speaker: c.speaker,
        cameraOff: c.cameraOff,
        elapsed: elapsed,
        error: c.error,
        quality: c.quality,
        remote: c.video && c.remote.srcObject != null
            ? RTCVideoView(
                c.remote,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : null,
        local: c.video && c.local.srcObject != null && !c.cameraOff
            ? RTCVideoView(
                c.local,
                mirror: c.frontCamera,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : null,
        onBack: () => Navigator.pop(context),
        onMute: c.toggleMute,
        onSpeaker: c.toggleSpeaker,
        onCamera: c.toggleCamera,
        onFlip: c.switchCamera,
        onVoice: c.switchToVoice,
        onAccept: () => c.answer(c.id!),
        onEnd: () =>
            c.incoming && c.state == 'ringing' ? c.decline(c.id!) : c.end(),
      );
    },
  );
}

class CallView extends StatefulWidget {
  const CallView({
    super.key,
    required this.peer,
    required this.state,
    required this.video,
    required this.incoming,
    required this.active,
    this.muted = false,
    this.speaker = false,
    this.cameraOff = false,
    this.elapsed = Duration.zero,
    this.error,
    this.quality = '',
    this.remote,
    this.local,
    required this.onBack,
    this.onMute,
    this.onSpeaker,
    this.onCamera,
    this.onFlip,
    this.onVoice,
    this.onAccept,
    this.onEnd,
  });
  final Person peer;
  final String state, quality;
  final bool video, incoming, active, muted, speaker, cameraOff;
  final Duration elapsed;
  final String? error;
  final Widget? remote, local;
  final VoidCallback onBack;
  final VoidCallback? onMute,
      onSpeaker,
      onCamera,
      onFlip,
      onVoice,
      onAccept,
      onEnd;
  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  Offset? pip;
  String get status => switch (widget.state) {
    'initiating' => 'Menyiapkan panggilan…',
    'ringing' => widget.incoming ? 'Panggilan masuk' : 'Memanggil…',
    'connecting' => 'Menghubungkan…',
    'connected' => clock(widget.elapsed),
    'reconnecting' => 'Menyambungkan kembali…',
    'declined' => 'Panggilan ditolak',
    'missed' => 'Tidak terjawab',
    'failed' => 'Panggilan gagal',
    _ => 'Panggilan berakhir',
  };
  Widget action(
    String label,
    IconData icon,
    VoidCallback? callback, {
    bool selected = false,
    Color? color,
  }) => SizedBox(
    width: 76,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: label,
          onPressed: callback,
          style: IconButton.styleFrom(
            minimumSize: const Size(52, 52),
            backgroundColor:
                color ??
                (selected ? Colors.white : Colors.white.withValues(alpha: .12)),
            foregroundColor: selected ? const Color(0xFF0F172A) : Colors.white,
            disabledBackgroundColor: Colors.white10,
          ),
          icon: Icon(icon, size: 25),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final w = widget;
    final ringing = w.incoming && w.state == 'ringing';
    return Scaffold(
      backgroundColor: const Color(0xFF080D18),
      body: LayoutBuilder(
        builder: (context, bounds) {
          final compact = bounds.maxHeight < 580;
          final pipWidth = (bounds.maxWidth * .27).clamp(84.0, 128.0),
              pipHeight = compact ? 116.0 : 164.0;
          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -.35),
                      radius: 1.15,
                      colors: [Color(0xFF1E3A64), Color(0xFF080D18)],
                    ),
                  ),
                ),
              ),
              if (w.video && w.remote != null)
                Positioned.fill(child: w.remote!),
              if (w.video)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black54,
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black87,
                          ],
                          stops: [0, .24, .6, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: w.active
                                ? 'Minimalkan panggilan'
                                : 'Kembali',
                            onPressed: w.onBack,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              w.video ? 'Panggilan video' : 'Panggilan suara',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.lock_outline,
                            size: 13,
                            color: Colors.white60,
                          ),
                          const SizedBox(width: 5),
                          if (MediaQuery.textScalerOf(context).scale(1) < 1.5)
                            const Text(
                              'Terenkripsi',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: w.video && w.remote != null
                            ? const SizedBox.shrink()
                            : SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: .09,
                                          ),
                                        ),
                                        color: Colors.white.withValues(
                                          alpha: .04,
                                        ),
                                      ),
                                      child: Avatar(
                                        w.peer,
                                        radius: compact ? 38 : 54,
                                      ),
                                    ),
                                    SizedBox(height: compact ? 12 : 20),
                                    Text(
                                      w.peer.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '@${w.peer.username}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      status,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: w.state == 'connected'
                                            ? const Color(0xFF93C5FD)
                                            : Colors.white70,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: 560,
                        maxHeight: bounds.maxHeight * .62,
                      ),
                      padding: EdgeInsets.fromLTRB(
                        12,
                        8,
                        12,
                        compact ? 12 : 20,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (w.video && w.remote != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  '${w.peer.name} · $status',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (w.error != null)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 90,
                                ),
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      w.error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFFDA4AF),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (w.quality.isNotEmpty && w.active)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  w.quality,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            if (w.active && !ringing)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .25),
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 4,
                                  runSpacing: 12,
                                  children: [
                                    action(
                                      w.muted ? 'Buka mic' : 'Bisukan',
                                      w.muted ? Icons.mic_off : Icons.mic,
                                      w.onMute,
                                      selected: w.muted,
                                    ),
                                    action(
                                      'Speaker',
                                      w.speaker
                                          ? Icons.volume_up
                                          : Icons.hearing,
                                      w.onSpeaker,
                                      selected: w.speaker,
                                    ),
                                    action(
                                      'Akhiri',
                                      Icons.call_end,
                                      w.onEnd,
                                      color: const Color(0xFFE5484D),
                                    ),
                                    if (w.video)
                                      action(
                                        'Kamera',
                                        w.cameraOff
                                            ? Icons.videocam_off
                                            : Icons.videocam,
                                        w.onCamera,
                                        selected: !w.cameraOff,
                                      ),
                                  ],
                                ),
                              ),
                            if (w.active && w.video && !ringing)
                              TextButton(
                                onPressed: w.onVoice,
                                child: const Text(
                                  'Lanjut dengan suara',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            SizedBox(height: compact ? 12 : 18),
                            if (w.active && ringing)
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 48,
                                runSpacing: 12,
                                children: [
                                  if (ringing)
                                    action(
                                      'Tolak',
                                      Icons.call_end,
                                      w.onEnd,
                                      color: const Color(0xFFE5484D),
                                    ),
                                  if (ringing)
                                    action(
                                      'Terima',
                                      w.video ? Icons.videocam : Icons.call,
                                      w.onAccept,
                                      color: const Color(0xFF16A36A),
                                    ),
                                ],
                              )
                            else if (!w.active)
                              OutlinedButton.icon(
                                onPressed: w.onBack,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Kembali ke chat'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (w.video && w.active && (w.local != null || w.cameraOff))
                Positioned(
                  left: (pip?.dx ?? (bounds.maxWidth - pipWidth - 16)).clamp(
                    8.0,
                    (bounds.maxWidth - pipWidth - 8).clamp(
                      8.0,
                      double.infinity,
                    ),
                  ),
                  top: (pip?.dy ?? (MediaQuery.paddingOf(context).top + 64))
                      .clamp(
                        MediaQuery.paddingOf(context).top + 56,
                        (bounds.maxHeight - pipHeight - 210).clamp(
                          MediaQuery.paddingOf(context).top + 56,
                          double.infinity,
                        ),
                      ),
                  width: pipWidth,
                  height: pipHeight,
                  child: GestureDetector(
                    onPanUpdate: (details) => setState(
                      () => pip =
                          (pip ??
                              Offset(
                                bounds.maxWidth - pipWidth - 16,
                                MediaQuery.paddingOf(context).top + 64,
                              )) +
                          details.delta,
                    ),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF172337),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white30, width: 1.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 16),
                        ],
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          w.local ??
                              const Center(
                                child: Icon(
                                  Icons.videocam_off,
                                  color: Colors.white54,
                                ),
                              ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              tooltip: 'Balik kamera',
                              onPressed: w.cameraOff ? null : w.onFlip,
                              icon: const Icon(
                                Icons.cameraswitch,
                                size: 21,
                                color: Colors.white,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black38,
                              ),
                            ),
                          ),
                          const Positioned(
                            left: 8,
                            bottom: 8,
                            child: Text(
                              'Kamu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                shadows: [Shadow(blurRadius: 8)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
