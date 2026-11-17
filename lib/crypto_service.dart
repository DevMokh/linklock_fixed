import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class LinkCryptoException implements Exception {
  const LinkCryptoException(this.message);

  final String message;

  @override
  String toString() => 'LinkCryptoException: $message';
}

/// Returns the 32-byte key kept on this device (see DeviceKeyStore).
typedef DeviceKeyProvider = Future<List<int>> Function();

/// Link encryption with no password. AES-GCM in two modes:
///
/// * Shareable (default): a fresh random key is generated per link and
///   stored inside the token itself, using AES-128. It opens on any device
///   that has the app. Putting the key in the token means this is
///   obfuscation, not secrecy, no matter how big the key is — so the token
///   uses the smaller, shorter key rather than paying for strength that
///   can't matter here.
/// * Device-only: the key lives in the device's secure storage and never
///   leaves it, using AES-256 for a real security margin. The token opens
///   only on this device.
///
/// Before encrypting, the link is deflate-compressed when that actually
/// makes it smaller (most real URLs: repeated "https://", "www.", common
/// words); otherwise the raw bytes are used as-is, so short or already-dense
/// links never get padded out.
///
/// Token = `LL3.` + base64url(bytes) without padding, where bytes are:
///   [0]      format version (3)
///   [1]      flags bitmask: bit0 = device-only mode, bit1 = compressed
///   [2..]    the key (16 or 32 bytes), present only in shareable mode
///   then     AES-GCM nonce (12 bytes), ciphertext, 16-byte tag
///
/// Everything before the nonce (version, flags, and the key when present) is
/// authenticated as AAD.
class LinkCrypto {
  LinkCrypto({required DeviceKeyProvider deviceKeyProvider, Random? random})
      : _deviceKeyProvider = deviceKeyProvider,
        _random = random ?? Random.secure();

  static const String prefix = 'LL3.';

  static const int _version = 3;
  static const int _flagDeviceOnly = 1 << 0;
  static const int _flagCompressed = 1 << 1;

  static const int _embeddedKeyLength = 16; // AES-128: travels with the token anyway.
  static const int _deviceKeyLength = 32; // AES-256: the real secrecy boundary.
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _headerLength = 2; // version + flags; key bytes (if any) follow.

  final DeviceKeyProvider _deviceKeyProvider;
  final Random _random;
  final AesGcm _cipher128 = AesGcm.with128bits();
  final AesGcm _cipher256 = AesGcm.with256bits();

  Future<String> encrypt(String link, {bool deviceOnly = false}) async {
    final text = link.trim();
    if (text.isEmpty) {
      throw const LinkCryptoException('اكتب الرابط الأول');
    }

    final rawBytes = Uint8List.fromList(utf8.encode(text));
    final (payload, compressed) = _maybeCompress(rawBytes);

    int flags = compressed ? _flagCompressed : 0;
    Uint8List embeddedKey = Uint8List(0);
    final List<int> key;
    final AesGcm cipher;

    if (deviceOnly) {
      flags |= _flagDeviceOnly;
      key = await _loadDeviceKey();
      cipher = _cipher256;
    } else {
      embeddedKey = _randomBytes(_embeddedKeyLength);
      key = embeddedKey;
      cipher = _cipher128;
    }

    final header = Uint8List.fromList([_version, flags, ...embeddedKey]);

    final box = await cipher.encrypt(
      payload,
      secretKey: SecretKey(key),
      nonce: _randomBytes(_nonceLength),
      aad: header,
    );

    // box.concatenation() = nonce + ciphertext + tag
    final out = BytesBuilder(copy: false)
      ..add(header)
      ..add(box.concatenation());
    return prefix + base64Url.encode(out.toBytes()).replaceAll('=', '');
  }

  Future<String> decrypt(String token) async {
    final compact = token.replaceAll(RegExp(r'\s+'), '');
    if (!compact.startsWith(prefix)) {
      throw const LinkCryptoException('ده مش نص مشفّر بالتطبيق ده');
    }

    Uint8List data;
    try {
      data = base64Url.decode(
        base64Url.normalize(compact.substring(prefix.length)),
      );
    } on FormatException {
      throw const LinkCryptoException('النص المشفّر ناقص أو متعدّل');
    }

    if (data.length < _headerLength + _nonceLength + _macLength) {
      throw const LinkCryptoException('النص المشفّر ناقص أو متعدّل');
    }
    if (data[0] != _version) {
      throw const LinkCryptoException('إصدار التشفير ده مش مدعوم');
    }

    final flags = data[1];
    final deviceOnly = flags & _flagDeviceOnly != 0;
    final compressed = flags & _flagCompressed != 0;

    final List<int> key;
    final AesGcm cipher;
    final int headerLength;

    if (deviceOnly) {
      headerLength = _headerLength;
      key = await _loadDeviceKey();
      cipher = _cipher256;
    } else {
      headerLength = _headerLength + _embeddedKeyLength;
      if (data.length < headerLength + _nonceLength + _macLength) {
        throw const LinkCryptoException('النص المشفّر ناقص أو متعدّل');
      }
      key = Uint8List.sublistView(data, _headerLength, headerLength);
      cipher = _cipher128;
    }

    final header = Uint8List.sublistView(data, 0, headerLength);
    final body = Uint8List.sublistView(data, headerLength);

    Uint8List clearBytes;
    try {
      final box = SecretBox.fromConcatenation(
        body,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await cipher.decrypt(box, secretKey: SecretKey(key), aad: header);
      clearBytes = Uint8List.fromList(clear);
    } catch (_) {
      throw LinkCryptoException(
        deviceOnly
            ? 'النص ده اتشفّر على جهاز تاني، أو مفتاح الجهاز اتغيّر أو اتمسح'
            : 'النص المشفّر اتعدّل أو ناقص',
      );
    }

    if (!compressed) return utf8.decode(clearBytes);

    try {
      final inflated = ZLibCodec().decode(clearBytes);
      return utf8.decode(inflated);
    } catch (_) {
      throw const LinkCryptoException('النص المشفّر ناقص أو متعدّل');
    }
  }

  Future<List<int>> _loadDeviceKey() async {
    try {
      final key = await _deviceKeyProvider();
      if (key.length != _deviceKeyLength) {
        throw const FormatException('unexpected key length');
      }
      return key;
    } catch (_) {
      throw const LinkCryptoException('مقدرتش أوصل لمفتاح الجهاز');
    }
  }

  /// Deflate-compresses [data] and returns it only if that's actually
  /// smaller; otherwise returns the original bytes unchanged. Compression is
  /// a size optimization, never a requirement, so any failure just falls
  /// back to the raw bytes.
  (Uint8List, bool) _maybeCompress(Uint8List data) {
    try {
      final compressed = Uint8List.fromList(ZLibCodec(level: 9).encode(data));
      if (compressed.length < data.length) {
        return (compressed, true);
      }
    } catch (_) {
      // Fall through to the uncompressed bytes below.
    }
    return (data, false);
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );
}
