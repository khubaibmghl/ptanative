import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// End-to-End Encryption (E2EE) Cipher for remote cloud relay messages
/// Derived from user pairing key with PBKDF2/SHA-256 keystream
class E2eeCipher {
  final Uint8List _keyBytes;

  E2eeCipher._(this._keyBytes);

  /// Factory from human-readable pairing key (e.g. 'pta_native_default')
  factory E2eeCipher.fromKey(String pairingKey) {
    final keyBytes = _deriveKey(pairingKey);
    return E2eeCipher._(keyBytes);
  }

  /// Encrypts plaintext JSON or string into Base64 ciphertext with randomized 16-byte IV
  String encrypt(String plaintext) {
    if (plaintext.isEmpty) return '';
    final plainBytes = utf8.encode(plaintext);
    final iv = _generateRandomBytes(16);

    final cipherBytes = _applyKeystream(plainBytes, _keyBytes, iv);

    // Combine IV (16 bytes) + Ciphertext + Simple HMAC-like checksum
    final checksum = _computeChecksum(cipherBytes, _keyBytes);
    final combined = Uint8List(16 + 4 + cipherBytes.length);
    combined.setRange(0, 16, iv);
    combined.setRange(16, 20, checksum);
    combined.setRange(20, combined.length, cipherBytes);

    return base64Encode(combined);
  }

  /// Decrypts Base64 ciphertext back to plaintext string. Returns null if key is invalid or corrupted.
  String? decrypt(String base64Ciphertext) {
    if (base64Ciphertext.isEmpty) return null;
    try {
      final combined = base64Decode(base64Ciphertext);
      if (combined.length < 20) return null; // Minimum 16 bytes IV + 4 bytes checksum

      final iv = combined.sublist(0, 16);
      final checksum = combined.sublist(16, 20);
      final cipherBytes = combined.sublist(20);

      final expectedChecksum = _computeChecksum(cipherBytes, _keyBytes);
      for (int i = 0; i < 4; i++) {
        if (checksum[i] != expectedChecksum[i]) {
          return null; // Key mismatch or payload corrupted
        }
      }

      final plainBytes = _applyKeystream(cipherBytes, _keyBytes, iv);
      return utf8.decode(plainBytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _generateRandomBytes(int length) {
    final rand = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rand.nextInt(256);
    }
    return bytes;
  }

  static Uint8List _computeChecksum(Uint8List data, Uint8List key) {
    var acc = 0x811c9dc5;
    for (final b in key) {
      acc = ((acc ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    for (final b in data) {
      acc = ((acc ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    final res = Uint8List(4);
    res[0] = (acc >> 24) & 0xFF;
    res[1] = (acc >> 16) & 0xFF;
    res[2] = (acc >> 8) & 0xFF;
    res[3] = acc & 0xFF;
    return res;
  }

  static Uint8List _deriveKey(String password) {
    final pwdBytes = utf8.encode(password);
    final salt = utf8.encode('PTA_NATIVE_SECURE_SALT_2026');
    var hash = _sha256(Uint8List.fromList([...pwdBytes, ...salt]));
    // 1000 rounds of key stretching
    for (int i = 0; i < 1000; i++) {
      hash = _sha256(hash);
    }
    return hash;
  }

  static Uint8List _applyKeystream(List<int> data, Uint8List key, Uint8List iv) {
    final out = Uint8List(data.length);
    var blockIndex = 0;
    Uint8List blockKeystream = _sha256(Uint8List.fromList([...key, ...iv, blockIndex]));
    var streamIdx = 0;

    for (int i = 0; i < data.length; i++) {
      if (streamIdx >= blockKeystream.length) {
        blockIndex++;
        blockKeystream = _sha256(Uint8List.fromList([...key, ...iv, blockIndex]));
        streamIdx = 0;
      }
      out[i] = data[i] ^ blockKeystream[streamIdx++];
    }
    return out;
  }

  /// Pure Dart SHA-256 implementation
  static Uint8List _sha256(Uint8List message) {
    final k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];

    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    final bitLength = message.length * 8;
    final paddedLength = ((message.length + 8) ~/ 64 + 1) * 64;
    final padded = Uint8List(paddedLength);
    padded.setRange(0, message.length, message);
    padded[message.length] = 0x80;

    for (int i = 0; i < 8; i++) {
      padded[paddedLength - 1 - i] = (bitLength >> (i * 8)) & 0xFF;
    }

    final w = List<int>.filled(64, 0);

    for (int chunk = 0; chunk < paddedLength; chunk += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = (padded[chunk + i * 4] << 24) |
            (padded[chunk + i * 4 + 1] << 16) |
            (padded[chunk + i * 4 + 2] << 8) |
            padded[chunk + i * 4 + 3];
      }

      for (int i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (int i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ (~e & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xFFFFFFFF;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    final out = Uint8List(32);
    final values = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (int i = 0; i < 8; i++) {
      out[i * 4] = (values[i] >> 24) & 0xFF;
      out[i * 4 + 1] = (values[i] >> 16) & 0xFF;
      out[i * 4 + 2] = (values[i] >> 8) & 0xFF;
      out[i * 4 + 3] = values[i] & 0xFF;
    }
    return out;
  }

  static int _rotr(int val, int n) {
    return ((val >>> n) | (val << (32 - n))) & 0xFFFFFFFF;
  }
}
