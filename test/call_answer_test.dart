import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:adoetz_chat/core/call_service.dart';
import 'package:adoetz_chat/core/controller.dart';
import 'package:adoetz_chat/core/models.dart';
import 'package:adoetz_chat/core/native_call_ui.dart';
import 'package:adoetz_chat/core/vault.dart';

const callId = '30000000-0000-4000-8000-000000000001';

class AnswerController extends ChatController {
  AnswerController(SupabaseClient client)
    : super(vault: MemoryVault(), client: client) {
    me = const Person(id: 'bob', username: 'bob', name: 'Bob');
    deviceId = 'bob-phone';
    chats.add(
      Conversation(
        id: 'room',
        peer: const Person(id: 'alice', username: 'alice', name: 'Alice'),
      ),
    );
    messages.add(
      ChatMessage(
        id: 'offer',
        chatId: 'room',
        senderId: 'alice',
        text: '',
        at: DateTime.now(),
        kind: 'signal',
        data: {
          'call_id': callId,
          'type': 'offer',
          'sdp': 'fixture-offer',
          'origin_device': 'alice-phone',
        },
      ),
    );
  }
  final signals = <Map<String, dynamic>>[];
  Completer<void>? syncGate;
  @override
  Future<void> sync() async {
    await syncGate?.future;
  }

  @override
  Future<void> send(
    Conversation chat,
    String text, {
    String kind = 'text',
    Map<String, dynamic>? data,
    VoidCallback? onCommitted,
  }) async {
    signals.add(data!);
    onCommitted?.call();
  }
}

class AnswerUi extends NativeCallUi {
  bool visible = false, ringing = true;
  String? pending;
  int claims = 0, starts = 0;
  final order = <String>[];
  @override
  Future<bool> foreground() async => visible;
  @override
  Future<String?> pendingAnswer() async => pending;
  @override
  Future<void> clearPending(String id) async {
    if (pending == id) pending = null;
  }

  @override
  Future<void> claim(Map<String, dynamic> params) async {
    claims++;
    ringing = false;
    order.add('claim');
  }

  @override
  Future<void> start(Map<String, dynamic> params) async {
    expect(visible, true);
    starts++;
    order.add('service');
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  for (final popup in [true, false]) {
    for (final video in [false, true]) {
      test(
        '${popup ? 'popup' : 'in-app'} ${video ? 'video' : 'voice'} answer waits for foreground, adopts once and ignores old ring timeout',
        () async {
          final ui = AnswerUi()..pending = popup ? callId : null;
          var status = 'ringing',
              accepts = 0,
              ends = 0,
              captures = 0,
              texture = 0;
          final row = <String, dynamic>{
            'id': callId,
            'caller_id': 'alice',
            'caller_device': 'alice-phone',
            'conversation_id': 'room',
            'video': video,
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          };
          final requests = <String>[];
          final client = SupabaseClient(
            'https://test.invalid',
            'public-key',
            accessToken: () async => 'test',
            httpClient: MockClient((request) async {
              requests.add('${request.url.path} ${request.body}');
              dynamic result;
              if (request.url.path.endsWith('turn-credentials')) {
                result = {'iceServers': []};
              } else if (request.url.path.endsWith('call_action')) {
                final operation = jsonDecode(request.body)['operation'];
                if (operation == 'accept') {
                  accepts++;
                  status = 'connecting';
                  row['callee_device'] = 'bob-phone';
                }
                if (operation == 'connected') status = 'connected';
                if (operation == 'end') {
                  ends++;
                  status = 'ended';
                }
                result = {...row, 'status': status};
              } else {
                result = [];
              }
              return http.Response(
                jsonEncode(result),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }),
          );
          const rtc = MethodChannel('FlutterWebRTC.Method');
          binding.defaultBinaryMessenger.setMockMethodCallHandler(rtc, (
            call,
          ) async {
            if (call.method == 'createVideoRenderer') {
              return {'textureId': ++texture};
            }
            if (call.method == 'getUserMedia') {
              expect(
                ui.visible,
                true,
                reason:
                    'Never capture while the popup is still handing off to MainActivity',
              );
              captures++;
              ui.order.add('capture');
              expect(
                (call.arguments as Map)['constraints']['video'],
                video ? isA<Map>() : false,
              );
              return {
                'streamId': 'stream',
                'audioTracks': [],
                'videoTracks': [],
              };
            }
            if (call.method == 'createPeerConnection') {
              return {'peerConnectionId': 'pc'};
            }
            if (call.method == 'createAnswer') {
              return {'sdp': 'fixture-answer', 'type': 'answer'};
            }
            if (call.method == 'getRemoteDescription') {
              return {'sdp': 'fixture-offer', 'type': 'offer'};
            }
            if (call.method == 'getStats') return {'stats': []};
            return null;
          });
          const callkit = MethodChannel('flutter_callkit_incoming');
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            callkit,
            (call) async => call.method == 'activeCalls' ? [] : null,
          );
          for (final name in [
            'flutter_callkit_incoming_events',
            'FlutterWebRTC.Event',
            'FlutterWebRTC/Texture1',
            'FlutterWebRTC/Texture2',
            'FlutterWebRTC/peerConnectionEventpc',
          ]) {
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel(name),
              (call) async => null,
            );
          }
          Future<void> event(String channel, Map<String, dynamic> value) async {
            final done = Completer<void>();
            binding.defaultBinaryMessenger.handlePlatformMessage(
              channel,
              const StandardMethodCodec().encodeSuccessEnvelope(value),
              (_) => done.complete(),
            );
            await done.future;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }

          final controller = AnswerController(client)
            ..syncGate = Completer<void>();
          final failures = <Object>[];
          final calls = CallService(
            controller,
            nativeUi: ui,
            onFailure: (error, stack) => failures.add('$error $stack'),
          );
          try {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            expect(accepts, 0);
            expect(captures, 0);
            expect(ui.ringing, true);
            ui.visible = true;
            if (!popup) unawaited(calls.answer(callId));
            for (var n = 0; n < 100 && accepts == 0; n++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            expect(
              accepts,
              1,
              reason: '${calls.error ?? calls.state} $requests $failures',
            );
            expect(ui.ringing, false);
            expect(
              captures,
              0,
              reason:
                  'Dismiss the ring even while encrypted offer sync is pending',
            );
            final duplicate = calls.answer(callId);
            controller.syncGate!.complete();
            controller.syncGate = null;
            await duplicate;
            for (var n = 0; n < 100 && captures == 0; n++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(calls.error, isNull);
            expect(accepts, 1);
            expect(captures, 1);
            expect(ui.claims, 1);
            expect(ui.starts, 1);
            expect(ui.order, ['claim', 'capture', 'service']);
            expect(
              controller.signals
                  .where((signal) => signal['type'] == 'answer')
                  .length,
              1,
            );
            await event('FlutterWebRTC/peerConnectionEventpc', {
              'event': 'peerConnectionState',
              'state': 'connected',
            });
            expect(calls.state, 'connected');
            await event('flutter_callkit_incoming_events', {
              'event':
                  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT',
              'body': {'id': callId},
            });
            expect(
              ends,
              0,
              reason:
                  'The original notification timer is obsolete after acceptance',
            );
            expect(calls.state, 'connected');
            expect(ui.pending, isNull);
          } finally {
            await calls.end();
            calls.dispose();
            controller.dispose();
            await client.dispose();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        },
      );
    }
  }
}
