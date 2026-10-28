import 'package:flutter/services.dart';

class DeviceRuntime {
  static const _channel = MethodChannel('adoetz/device_runtime');
  static Future<String> acquire() async =>
      (await _channel.invokeMethod<String>('acquire'))!;
  static Future<void> release(String token) =>
      _channel.invokeMethod('release', token);
  static Future<void> protectScreen(bool enabled) =>
      _channel.invokeMethod('protect', enabled);
  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod('notificationSettings');
  static Future<void> flushSecureStorage() => _channel.invokeMethod('flush');
}
