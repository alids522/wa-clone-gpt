import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:uuid/uuid.dart';
import 'controller.dart';
import 'models.dart';

class CallService extends ChangeNotifier {
  CallService(this.controller) {
    _instances[controller] = this;
    _events = controller.events.stream.listen((_) => _processSignals());
    _native = FlutterCallkitIncoming.onEvent.listen((event) {
      if (event is CallEventActionCallAccept) {
        answer(event.callKitParams.id).catchError(_failure);
      }
      if (event is CallEventActionCallDecline) {
        decline(event.callKitParams.id).catchError(_failure);
      }
      if (event is CallEventActionCallEnded && event.callKitParams.id == id) {
        end().catchError(_failure);
      }
      if (event is CallEventActionCallTimeout && event.id == id) {
        end().catchError(_failure);
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _restoreNative();
  }
  static final _instances = Expando<CallService>();
  static CallService of(ChatController c) => _instances[c]!;
  final ChatController controller;
  VoidCallback? onShow;
  String? id, error;
  Conversation? chat;
  String state = 'idle';
  String quality = '';
  bool incoming = false,
      video = false,
      muted = false,
      speaker = false,
      cameraOff = false;
  DateTime? connectedAt;
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  bool _renderers = false,
      _polling = false,
      _closing = false,
      _disposed = false,
      _descriptionSent = false;
  bool _answering = false;
  Timer? _timer, _disconnect, _candidateTimer;
  StreamSubscription<ChatMessage>? _events;
  StreamSubscription<CallEvent?>? _native;
  Future<void> _signals = Future.value();
  final _seen = <String>{};
  final _outgoingCandidates = <Map<String, dynamic>>[];
  final _pendingCandidates = <RTCIceCandidate>[];
  Map<String, dynamic>? _row;
  DateTime _heartbeat = DateTime(2000), _turnRefresh = DateTime(2000);
  bool get active =>
      id != null &&
      !['idle', 'ended', 'failed', 'declined', 'missed'].contains(state);

  Future<Map<String, dynamic>> _action(
    String operation, {
    String? callId,
    Conversation? room,
    bool? withVideo,
  }) async => Map<String, dynamic>.from(
    await controller.client!.rpc(
      'call_action',
      params: {
        'call_id': callId ?? id,
        'device': controller.deviceId,
        'operation': operation,
        if (room != null) 'chat': room.id,
        'is_video': ?withVideo,
      },
    ),
  );
  Future<void> _restoreNative() async {
    try {
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        if (call.isAccepted) {
          await answer(call.id);
          return;
        }
      }
      await _poll();
    } catch (_) {}
  }

  void _failure(Object _) {
    if (state == 'ended' || _closing) return;
    error =
        'Panggilan belum dapat tersambung. Periksa izin mikrofon dan koneksi.';
    end(failed: true).catchError((Object _) {});
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(Conversation room, {required bool withVideo}) async {
    if (_closing || _answering) return;
    if (controller.preview || controller.deviceId == null) {
      throw StateError('Masuk untuk menelepon.');
    }
    if (active) {
      onShow?.call();
      return;
    }
    await _release();
    id = const Uuid().v4();
    final startedId = id!;
    chat = room;
    video = withVideo;
    incoming = false;
    muted = false;
    cameraOff = false;
    quality = '';
    error = null;
    state = 'initiating';
    _notify();
    onShow?.call();
    try {
      final row = await _action(
        'start',
        callId: startedId,
        room: room,
        withVideo: withVideo,
      );
      if (!_validCall(startedId)) {
        await _action('end', callId: startedId);
        return;
      }
      _row = row;
      await _prepare();
      if (!_validCall(startedId)) return;
      await FlutterCallkitIncoming.startCall(
        CallKitParams(
          id: id!,
          nameCaller: room.peer.name,
          appName: 'Adoetz Chat',
          handle: '@${room.peer.username}',
          type: video ? 1 : 0,
        ),
      );
      final offer = await _pc!.createOffer();
      if (!_validCall(startedId)) return;
      await _pc!.setLocalDescription(offer);
      if (!_validCall(startedId)) return;
      await _signal({'type': 'offer', 'sdp': offer.sdp, 'video': video});
      _descriptionSent = true;
      await _flushCandidates();
      if (!_validCall(startedId)) return;
      state = 'ringing';
      _notify();
    } catch (e) {
      if (id == startedId && active) _failure(e);
    }
  }

  Future<void> answer(String callId) async {
    if (_closing) return;
    if (_answering ||
        (id == callId &&
            _pc != null &&
            ['connecting', 'connected'].contains(state))) {
      return;
    }
    _answering = true;
    try {
      await _answerInternal(callId);
    } catch (e) {
      _failure(e);
    } finally {
      _answering = false;
    }
  }

  Future<void> _answerInternal(String callId) async {
    if (active && id == callId && !incoming) return;
    final row = await _action('get', callId: callId);
    if (!['ringing', 'connecting'].contains(row['status']) ||
        row['caller_id'] == controller.me?.id) {
      return;
    }
    if (active && id != callId) {
      throw StateError('Panggilan lain sedang aktif.');
    }
    id = callId;
    incoming = true;
    _row = row;
    chat = controller.chats
        .where((c) => c.id == row['conversation_id'])
        .firstOrNull;
    if (chat == null) {
      await controller.sync();
      chat = controller.chats.firstWhere((c) => c.id == row['conversation_id']);
    }
    video = row['video'] == true;
    state = 'connecting';
    error = null;
    _notify();
    onShow?.call();
    try {
      _row = await _action('accept');
      await controller.sync();
      ChatMessage? offer;
      for (var attempt = 0; attempt < 8 && offer == null; attempt++) {
        offer = controller.messages
            .where(
              (m) =>
                  m.kind == 'signal' &&
                  m.data['call_id'] == id &&
                  m.data['type'] == 'offer' &&
                  m.senderId == row['caller_id'] &&
                  m.data['origin_device'] == row['caller_device'],
            )
            .firstOrNull;
        if (offer == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await controller.sync();
        }
      }
      if (offer == null) throw StateError('Offer belum tersedia.');
      await _prepare();
      await _pc!.setRemoteDescription(
        RTCSessionDescription(offer.data['sdp'], 'offer'),
      );
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _signal({'type': 'answer', 'sdp': answer.sdp, 'video': video});
      _descriptionSent = true;
      await _flushCandidates();
      await _drainCandidates();
      _processSignals();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> decline(String callId) async {
    try {
      await _action('decline', callId: callId);
    } finally {
      await FlutterCallkitIncoming.endCall(callId);
      if (id == callId) {
        state = 'declined';
        await _release();
        _notify();
      }
    }
  }

  bool _validCall(String callId) => id == callId && active && !_closing;
  Future<void> _prepare() async {
    final preparingId = id!;
    if (!_validCall(preparingId)) throw StateError('Call cancelled');
    if (!_renderers) {
      await local.initialize();
      await remote.initialize();
      _renderers = true;
    }
    MediaStream candidate;
    try {
      candidate = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video
            ? {
                'facingMode': 'user',
                'width': 640,
                'height': 480,
                'frameRate': 24,
              }
            : false,
      });
    } catch (_) {
      if (!_validCall(preparingId)) rethrow;
      if (!video) rethrow;
      video = false;
      cameraOff = true;
      candidate = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    }
    if (!_validCall(preparingId)) {
      for (final t in candidate.getTracks()) {
        await t.stop();
      }
      await candidate.dispose();
      throw StateError('Call cancelled');
    }
    _stream = candidate;
    local.srcObject = _stream;
    for (final track in _stream!.getAudioTracks()) {
      track.enabled = !muted;
    }
    final config = await _iceConfig();
    if (!_validCall(preparingId)) throw StateError('Call cancelled');
    final peerConnection = await createPeerConnection({
      ...config,
      'sdpSemantics': 'unified-plan',
    });
    if (!_validCall(preparingId)) {
      await peerConnection.close();
      throw StateError('Call cancelled');
    }
    _pc = peerConnection;
    for (final track in _stream!.getTracks()) {
      await _pc!.addTrack(track, _stream!);
    }
    _pc!.onTrack = (event) {
      if (_pc != peerConnection || !_validCall(preparingId)) return;
      if (event.streams.isNotEmpty) {
        remote.srcObject = event.streams.first;
        _notify();
      }
    };
    _pc!.onIceCandidate = (candidate) {
      if (_pc != peerConnection || !_validCall(preparingId)) return;
      if (candidate.candidate == null) return;
      _outgoingCandidates.add(candidate.toMap());
      _candidateTimer?.cancel();
      _candidateTimer = Timer(const Duration(milliseconds: 200), () {
        _flushCandidates().catchError(_failure);
      });
    };
    _pc!.onConnectionState = (connection) async {
      if (_pc != peerConnection || !_validCall(preparingId) || _disposed) {
        return;
      }
      if (connection ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _disconnect?.cancel();
        state = 'connected';
        connectedAt ??= DateTime.now();
        try {
          _row = await _action('connected');
          await FlutterCallkitIncoming.setCallConnected(id!);
        } catch (_) {}
        _notify();
      } else if (connection ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        state = 'reconnecting';
        _notify();
        _disconnect?.cancel();
        _disconnect = Timer(const Duration(seconds: 25), () {
          end(failed: true);
        });
        if (!incoming) _restartIce().catchError(_failure);
      } else if (connection ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _failure(StateError('ICE failed'));
      }
    };
    speaker = video;
    await Helper.setSpeakerphoneOn(speaker);
  }

  Future<void> _restartIce() async {
    if (_pc == null || !active) return;
    final offer = await _pc!.createOffer({'iceRestart': true});
    await _pc!.setLocalDescription(offer);
    await _signal({'type': 'offer', 'restart': true, 'sdp': offer.sdp});
  }

  Future<Map<String, dynamic>> _iceConfig() async {
    final result = await controller.client!.functions.invoke(
      'turn-credentials',
      body: {'call_id': id, 'device': controller.deviceId},
    );
    if (result.data?['iceServers'] == null) {
      throw StateError('TURN relay belum siap.');
    }
    _turnRefresh = DateTime.now();
    return {'iceServers': result.data['iceServers']};
  }

  Future<void> _signal(Map<String, dynamic> data) => controller.send(
    chat!,
    'Sinyal panggilan',
    kind: 'signal',
    data: {'call_id': id, ...data},
  );
  Future<void> _flushCandidates() async {
    if (!_descriptionSent || _outgoingCandidates.isEmpty || !active) return;
    final batch = _outgoingCandidates.take(30).toList();
    _outgoingCandidates.removeRange(0, batch.length);
    await _signal({'type': 'ice', 'candidates': batch});
    if (_outgoingCandidates.isNotEmpty) await _flushCandidates();
  }

  void _processSignals() {
    _signals = _signals
        .then<void>((_) async {
          for (final m
              in controller.messages
                  .where(
                    (m) =>
                        m.kind == 'signal' && m.senderId != controller.me?.id,
                  )
                  .toList()) {
            if (_seen.contains(m.id) ||
                m.data['call_id'] != id ||
                _pc == null) {
              continue;
            }
            final row = _row;
            if (row == null) continue;
            final expected = incoming
                ? row['caller_device']
                : row['callee_device'];
            if (m.data['origin_device'] != expected) continue;
            _seen.add(m.id);
            if (m.data['type'] == 'answer' && !incoming) {
              await _pc!.setRemoteDescription(
                RTCSessionDescription(m.data['sdp'], 'answer'),
              );
              await _drainCandidates();
            } else if (m.data['type'] == 'offer' &&
                m.data['restart'] == true &&
                incoming) {
              await _pc!.setRemoteDescription(
                RTCSessionDescription(m.data['sdp'], 'offer'),
              );
              final response = await _pc!.createAnswer();
              await _pc!.setLocalDescription(response);
              await _signal({
                'type': 'answer',
                'sdp': response.sdp,
                'restart': true,
              });
              await _drainCandidates();
            } else if (m.data['type'] == 'media' && m.data['video'] == false) {
              video = false;
              _notify();
            } else if (m.data['type'] == 'ice') {
              for (final candidate in (m.data['candidates'] as List).take(30)) {
                _pendingCandidates.add(
                  RTCIceCandidate(
                    candidate['candidate'],
                    candidate['sdpMid'],
                    candidate['sdpMLineIndex'],
                  ),
                );
              }
              await _drainCandidates();
            }
          }
        })
        .catchError(_failure);
  }

  Future<void> _drainCandidates() async {
    if (_pc == null || await _pc!.getRemoteDescription() == null) return;
    while (_pendingCandidates.isNotEmpty) {
      await _pc!.addCandidate(_pendingCandidates.removeAt(0));
    }
  }

  Future<void> _poll() async {
    if (_polling ||
        _disposed ||
        controller.me == null ||
        controller.preview ||
        controller.deviceId == null) {
      return;
    }
    _polling = true;
    try {
      if (active) {
        final row = await _action('get');
        _row = row;
        if (['ended', 'declined', 'missed', 'failed'].contains(row['status']) ||
            (incoming &&
                row['callee_device'] != null &&
                row['callee_device'] != controller.deviceId)) {
          state = row['status'] == 'connecting' ? 'ended' : row['status'];
          await _release();
          _notify();
          return;
        }
        if (['connecting', 'connected', 'reconnecting'].contains(state) &&
            DateTime.now().difference(_heartbeat).inSeconds >= 15) {
          await _action('heartbeat');
          _heartbeat = DateTime.now();
        }
        if (_pc != null &&
            DateTime.now().difference(_turnRefresh).inMinutes >= 5) {
          await _pc!.setConfiguration(await _iceConfig());
        }
        _processSignals();
        if (_pc != null && state == 'connected') {
          final stats = await _pc!.getStats();
          final inbound = stats
              .where(
                (s) => s.type == 'inbound-rtp' && s.values['jitter'] is num,
              )
              .firstOrNull;
          if (inbound != null) {
            final jitter = inbound.values['jitter'] as num;
            quality = jitter > .08
                ? 'Koneksi kurang stabil'
                : jitter > .03
                ? 'Koneksi cukup'
                : 'Koneksi baik';
          }
        }
        _notify();
      } else {
        final rows = await controller.client!
            .from('calls')
            .select()
            .eq('status', 'ringing')
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at', ascending: false)
            .limit(5);
        final row = rows
            .where((r) => r['caller_id'] != controller.me?.id)
            .firstOrNull;
        if (row != null) {
          id = row['id'];
          _row = row;
          incoming = true;
          state = 'ringing';
          video = row['video'];
          chat = controller.chats
              .where((c) => c.id == row['conversation_id'])
              .firstOrNull;
          if (chat != null) {
            _notify();
            onShow?.call();
          }
        }
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  Future<void> toggleMute() async {
    muted = !muted;
    for (final track in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    _notify();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    _notify();
  }

  Future<void> toggleCamera() async {
    cameraOff = !cameraOff;
    for (final t in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !cameraOff;
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final tracks = _stream?.getVideoTracks();
    if (tracks != null && tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  Future<void> switchToVoice() async {
    for (final track in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    video = false;
    cameraOff = true;
    _notify();
    if (active) await _signal({'type': 'media', 'video': false});
  }

  Future<void> end({bool failed = false}) async {
    if (_closing || (!active && _pc == null && _stream == null)) return;
    _closing = true;
    state = failed ? 'failed' : 'ended';
    await _release();
    _notify();
    try {
      if (id != null) await _action('end').timeout(const Duration(seconds: 5));
    } catch (_) {}
    _closing = false;
    _notify();
  }

  Future<void> _release() async {
    _disconnect?.cancel();
    _candidateTimer?.cancel();
    final connection = _pc;
    _pc = null;
    final stream = _stream;
    _stream = null;
    if (_renderers) {
      local.srcObject = null;
      remote.srcObject = null;
    }
    for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = false;
      await track.stop();
    }
    await stream?.dispose();
    await connection?.close();
    if (id != null) {
      try {
        await FlutterCallkitIncoming.endCall(id!);
      } catch (_) {}
    }
    _pendingCandidates.clear();
    _outgoingCandidates.clear();
    _seen.clear();
    _descriptionSent = false;
    connectedAt = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _events?.cancel();
    _native?.cancel();
    end().whenComplete(() async {
      if (_renderers) {
        await local.dispose();
        await remote.dispose();
      }
    });
    _instances[controller] = null;
    super.dispose();
  }
}
