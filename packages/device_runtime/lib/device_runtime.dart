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
  static Future<bool> authenticate() async =>
      await _channel.invokeMethod<bool>('authenticate') ?? false;
  static Future<void> backgroundApp() => _channel.invokeMethod('background');
  static Future<Map<String, dynamic>> mediaPreview(
    String path,
    String mime,
  ) async => Map<String, dynamic>.from(
    await _channel.invokeMethod('mediaPreview', {'path': path, 'mime': mime}) ??
        {},
  );
  static Future<String?> saveFile(
    String path,
    String name,
    String mime, {
    bool chooseLocation = false,
  }) => _channel.invokeMethod<String>('saveFile', {
    'path': path,
    'name': name,
    'mime': mime,
    'choose': chooseLocation,
  });
}
