import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceVault implements Vault {
  const DeviceVault();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryVault implements Vault {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.vault);
  final Vault vault;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async =>
      await vault.read('auth_session') != null;
  @override
  Future<String?> accessToken() => vault.read('auth_session');
  @override
  Future<void> persistSession(String persistSessionString) =>
      vault.write('auth_session', persistSessionString);
  @override
  Future<void> removePersistedSession() => vault.delete('auth_session');
}

Future<Map<String, dynamic>> readJson(Vault vault, String key) async {
  final raw = await vault.read(key);
  return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw));
}
