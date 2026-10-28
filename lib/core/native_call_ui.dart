import 'package:flutter/services.dart';

class NativeCallUi {
  static const channel = MethodChannel('adoetz/call_ui');
  Future<bool> foreground() async =>
      await channel.invokeMethod<bool>('foreground') ?? false;
  Future<String?> pendingAnswer() =>
      channel.invokeMethod<String>('pendingAnswer');
  Future<void> clearPending(String id) =>
      channel.invokeMethod('clearPending', id);
  Future<void> claim(Map<String, dynamic> params) =>
      channel.invokeMethod('claimIncoming', params);
  Future<void> start(Map<String, dynamic> params) =>
      channel.invokeMethod('startIncoming', params);
}
