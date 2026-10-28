import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app/widgets.dart';
import '../core/call_service.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({super.key, required this.service});
  final CallService service;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final c = service;
      final status = switch (c.state) {
        'initiating' => 'Menyiapkan panggilan…',
        'ringing' => c.incoming ? 'Panggilan masuk' : 'Memanggil…',
        'connecting' => 'Menghubungkan…',
        'connected' => 'Terhubung',
        'reconnecting' => 'Menyambungkan kembali…',
        'declined' => 'Panggilan ditolak',
        'missed' => 'Tidak terjawab',
        'failed' => 'Panggilan gagal',
        _ => 'Panggilan berakhir',
      };
      return Scaffold(
        appBar: AppBar(
          title: Text(c.video ? 'Panggilan video' : 'Panggilan suara'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (c.video && c.remote.srcObject != null)
                      Positioned.fill(
                        child: RTCVideoView(
                          c.remote,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      )
                    else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (c.chat != null) Avatar(c.chat!.peer, radius: 54),
                          const SizedBox(height: 24),
                          Text(
                            c.chat?.peer.name ?? 'Adoetz Chat',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    if (c.video && c.local.srcObject != null && !c.cameraOff)
                      Positioned(
                        right: 16,
                        top: 16,
                        width: 110,
                        height: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: RTCVideoView(
                            c.local,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(c.error!, textAlign: TextAlign.center),
                ),
              if (c.quality.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(c.quality),
                ),
              if (c.active && c.video)
                TextButton(
                  onPressed: c.switchToVoice,
                  child: const Text('Lanjut dengan suara'),
                ),
              if (c.active && !(c.incoming && c.state == 'ringing'))
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  children: [
                    IconButton.filledTonal(
                      tooltip: c.muted ? 'Aktifkan mikrofon' : 'Bisukan',
                      onPressed: c.toggleMute,
                      icon: Icon(c.muted ? Icons.mic_off : Icons.mic),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Speaker',
                      onPressed: c.toggleSpeaker,
                      icon: Icon(c.speaker ? Icons.volume_up : Icons.hearing),
                    ),
                    if (c.video)
                      IconButton.filledTonal(
                        tooltip: 'Video aktif/nonaktif',
                        onPressed: c.toggleCamera,
                        icon: Icon(
                          c.cameraOff ? Icons.videocam_off : Icons.videocam,
                        ),
                      ),
                    if (c.video)
                      IconButton.filledTonal(
                        tooltip: 'Ganti kamera',
                        onPressed: c.switchCamera,
                        icon: const Icon(Icons.cameraswitch),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (c.incoming && c.state == 'ringing')
                      FilledButton.icon(
                        onPressed: () => c.answer(c.id!),
                        icon: const Icon(Icons.call),
                        label: const Text('Terima'),
                      ),
                    if (c.active)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                        ),
                        onPressed: () => c.incoming && c.state == 'ringing'
                            ? c.decline(c.id!)
                            : c.end(),
                        icon: const Icon(Icons.call_end),
                        label: Text(
                          c.incoming && c.state == 'ringing'
                              ? 'Tolak'
                              : 'Akhiri',
                        ),
                      )
                    else
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tutup'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
