import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps one random 32-byte key in the platform's secure storage
/// (Android Keystore / iOS Keychain). Created on first use.
class DeviceKeyStore {
  DeviceKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyName = 'linklock_device_key_v1';
  static const int _keyLength = 32;

  final FlutterSecureStorage _storage;

  Future<List<int>> getOrCreateKey() async {
    final stored = await _storage.read(key: _keyName);
    if (stored != null) {
      try {
        final bytes = base64Decode(stored);
        if (bytes.length == _keyLength) return bytes;
      } on FormatException {
        // Corrupt value: fall through and create a new key.
      }
    }

    return rotateKey();
  }

  /// True once a device key exists (so the caller can word a rotation
  /// warning correctly before there's anything to lose).
  Future<bool> hasKey() async {
    return (await _storage.read(key: _keyName)) != null;
  }

  /// Replaces the device key with a brand-new random one.
  ///
  /// Anything encrypted in "device-only" mode under the old key becomes
  /// permanently unreadable — on this device or any other — the moment this
  /// returns. That's the point: it's how you deliberately cut off every
  /// link locked that way so far.
  Future<List<int>> rotateKey() async {
    final random = Random.secure();
    final bytes = List<int>.generate(_keyLength, (_) => random.nextInt(256));
    await _storage.write(key: _keyName, value: base64Encode(bytes));
    return bytes;
  }
}
