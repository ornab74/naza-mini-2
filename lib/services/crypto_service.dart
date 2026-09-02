import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import 'linux_crypto.dart';
import 'linux_oqs.dart';

class NazaCryptoService {
  NazaCryptoService();

  static final _smallMagic = utf8.encode('NAZA-DART-AES-GCM-v1\n');
  static final _streamMagic = utf8.encode('NAZA-DART-AES-GCM-CHUNK-v1\n');
  static final _pqMagic = utf8.encode('NAZA-ML-KEM-768-AES-GCM-v1\n');
  // Larger chunks reduce per-operation overhead. Linux uses OpenSSL's native
  // AES-GCM fast path; the Dart fallback also benefits from fewer operations.
  static const chunkSize = 16 * 1024 * 1024;
  static const nonceSize = 12;
  static const macSize = 16;

  // Ask cryptography_flutter directly for AES-GCM. On Android, iOS, and
  // macOS this selects the platform implementation instead of waiting for a
  // pure-Dart cipher to be chosen by accident. Linux uses OpenSSL below.
  final AesGcm _aes = FlutterCryptography().aesGcm(secretKeyLength: 32);
  final LinuxOpenSslAesGcm? _native = LinuxOpenSslAesGcm.tryOpen();
  final LinuxLibOqs? _oqs = LinuxLibOqs.tryOpen();
  final Random _random = Random.secure();

  String get backendLabel {
    if (_native != null) {
      return _oqs == null
          ? 'OpenSSL AES-GCM'
          : 'OpenSSL AES-GCM + ML-KEM-768 (liboqs 0.14.0)';
    }
    if (FlutterCryptography.isPluginPresent &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return 'Native AES-GCM';
    }
    return 'Background AES-GCM';
  }

  bool get isPostQuantumAvailable => _oqs != null;

  MlKemKeyPair generatePostQuantumKeyPair() => _requireOqs().generateKeyPair();

  /// Encrypts to an ML-KEM-768 public key. HKDF-SHA-256 domain-separates the
  /// KEM secret before it is used as the AES-256-GCM content-encryption key.
  Future<Uint8List> encryptBytesPostQuantum(
    Uint8List clear,
    Uint8List recipientPublicKey,
  ) async {
    final encapsulation = _requireOqs().encapsulate(recipientPublicKey);
    try {
      final key = await _deriveKemKey(
        encapsulation.sharedSecret,
        encapsulation.ciphertext,
      );
      try {
        final encrypted = await encryptBytes(clear, key);
        return Uint8List.fromList(<int>[
          ..._pqMagic,
          ...encapsulation.ciphertext,
          ...encrypted,
        ]);
      } finally {
        key.fillRange(0, key.length, 0);
      }
    } finally {
      encapsulation.sharedSecret.fillRange(
        0,
        encapsulation.sharedSecret.length,
        0,
      );
    }
  }

  Future<Uint8List> decryptBytesPostQuantum(
    Uint8List payload,
    Uint8List recipientSecretKey,
  ) async {
    final headerLength = _pqMagic.length + LinuxLibOqs.ciphertextSize;
    if (payload.length < headerLength) {
      throw const FormatException('Post-quantum envelope is too short.');
    }
    if (!_constantTimeEquals(payload.sublist(0, _pqMagic.length), _pqMagic)) {
      throw const FormatException('Unknown post-quantum envelope format.');
    }
    final ciphertext = payload.sublist(_pqMagic.length, headerLength);
    final sharedSecret = _requireOqs().decapsulate(
      ciphertext,
      recipientSecretKey,
    );
    try {
      final key = await _deriveKemKey(sharedSecret, ciphertext);
      try {
        return await decryptBytes(payload.sublist(headerLength), key);
      } finally {
        key.fillRange(0, key.length, 0);
      }
    } finally {
      sharedSecret.fillRange(0, sharedSecret.length, 0);
    }
  }

  LinuxLibOqs _requireOqs() {
    final oqs = _oqs;
    if (oqs == null) {
      throw StateError(
        'Post-quantum encryption requires the pinned liboqs 0.14.0 Linux bundle.',
      );
    }
    return oqs;
  }

  Future<Uint8List> _deriveKemKey(
    Uint8List sharedSecret,
    Uint8List kemCiphertext,
  ) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: kemCiphertext,
      info: utf8.encode('NAZA ML-KEM-768 AES-256-GCM envelope v1'),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  Uint8List randomBytes(int count) => Uint8List.fromList(
    List<int>.generate(count, (_) => _random.nextInt(256)),
  );

  Uint8List generateKey() => randomBytes(32);

  Future<Uint8List> derivePassphraseKey(
    String passphrase,
    Uint8List salt,
  ) async {
    final pbkdf2 = Pbkdf2.hmacSha256(iterations: 250000, bits: 256);
    final key = await pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<Uint8List> encryptBytes(Uint8List clear, Uint8List keyBytes) async {
    final nonce = randomBytes(nonceSize);
    final native = _native;
    final cipherText;
    final mac;
    if (native != null) {
      final box = native.encrypt(clear, keyBytes, nonce);
      cipherText = box.cipherText;
      mac = box.mac;
    } else {
      final box = await _aes.encrypt(
        clear,
        secretKey: SecretKey(keyBytes),
        nonce: nonce,
      );
      cipherText = box.cipherText;
      mac = box.mac.bytes;
    }
    return Uint8List.fromList(<int>[
      ..._smallMagic,
      ...nonce,
      ...mac,
      ...cipherText,
    ]);
  }

  Future<Uint8List> decryptBytes(Uint8List payload, Uint8List keyBytes) async {
    if (payload.length < _smallMagic.length + nonceSize + macSize) {
      throw const FormatException('Encrypted payload is too short.');
    }
    final magic = payload.sublist(0, _smallMagic.length);
    if (!_constantTimeEquals(magic, _smallMagic)) {
      throw const FormatException('Unknown NAZA encrypted payload format.');
    }
    var offset = _smallMagic.length;
    final nonce = payload.sublist(offset, offset + nonceSize);
    offset += nonceSize;
    final mac = payload.sublist(offset, offset + macSize);
    offset += macSize;
    final cipherText = payload.sublist(offset);
    final native = _native;
    final clear = native != null
        ? native.decrypt(cipherText, keyBytes, nonce, mac)
        : await _aes.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
            secretKey: SecretKey(keyBytes),
          );
    return Uint8List.fromList(clear);
  }

  Future<String> sha256File(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return _hex(hash.bytes);
  }

  Future<void> encryptFileChunked(
    File source,
    File destination,
    Uint8List keyBytes, {
    void Function(double value)? onProgress,
  }) async {
    final temp = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    if (await temp.exists()) await temp.delete();
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await source.open(mode: FileMode.read);
      output = await temp.open(mode: FileMode.write);
      final total = await source.length();
      var processed = 0;
      await output.writeFrom(_streamMagic);
      await output.writeFrom(_u32(chunkSize));
      while (true) {
        final clear = await input.read(chunkSize);
        if (clear.isEmpty) break;
        final nonce = randomBytes(nonceSize);
        final native = _native;
        final cipherText;
        final mac;
        if (native != null) {
          final box = native.encrypt(clear, keyBytes, nonce);
          cipherText = box.cipherText;
          mac = box.mac;
        } else {
          final box = await _aes.encrypt(
            clear,
            secretKey: SecretKey(keyBytes),
            nonce: nonce,
          );
          cipherText = box.cipherText;
          mac = box.mac.bytes;
        }
        await output.writeFrom(_u32(clear.length));
        await output.writeFrom(nonce);
        await output.writeFrom(mac);
        await output.writeFrom(cipherText);
        processed += clear.length;
        onProgress?.call(total == 0 ? 1 : processed / total);
        await Future<void>.delayed(Duration.zero);
      }
      await output.flush();
      await input.close();
      input = null;
      await output.close();
      output = null;
      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);
      onProgress?.call(1);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    } finally {
      await input?.close();
      await output?.close();
    }
  }

  Future<void> decryptFileChunked(
    File source,
    File destination,
    Uint8List keyBytes, {
    void Function(double value)? onProgress,
  }) async {
    final temp = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    if (await temp.exists()) await temp.delete();
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await source.open(mode: FileMode.read);
      output = await temp.open(mode: FileMode.write);
      final total = await source.length();
      final magic = await input.read(_streamMagic.length);
      if (!_constantTimeEquals(magic, _streamMagic)) {
        throw const FormatException(
          'This .aes file is not a NAZA Dart chunked container. '
          'The Python streaming format is intentionally not treated as compatible.',
        );
      }
      final storedChunkSize = _readU32(await input.read(4));
      if (storedChunkSize <= 0 || storedChunkSize > 64 * 1024 * 1024) {
        throw const FormatException('Invalid encrypted model chunk size.');
      }
      while (true) {
        final lenBytes = await input.read(4);
        if (lenBytes.isEmpty) break;
        if (lenBytes.length != 4)
          throw const FormatException('Truncated chunk header.');
        final clearLength = _readU32(lenBytes);
        if (clearLength <= 0 || clearLength > storedChunkSize) {
          throw const FormatException('Invalid encrypted model chunk length.');
        }
        final nonce = await input.read(nonceSize);
        final mac = await input.read(macSize);
        final cipherText = await input.read(clearLength);
        if (nonce.length != nonceSize ||
            mac.length != macSize ||
            cipherText.length != clearLength) {
          throw const FormatException('Truncated encrypted model chunk.');
        }
        final native = _native;
        final clear = native != null
            ? native.decrypt(cipherText, keyBytes, nonce, mac)
            : await _aes.decrypt(
                SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
                secretKey: SecretKey(keyBytes),
              );
        await output.writeFrom(clear);
        final position = await input.position();
        onProgress?.call(total == 0 ? 1 : position / total);
        await Future<void>.delayed(Duration.zero);
      }
      await output.flush();
      await input.close();
      input = null;
      await output.close();
      output = null;
      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);
      onProgress?.call(1);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    } finally {
      await input?.close();
      await output?.close();
    }
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static int _readU32(List<int> bytes) {
    if (bytes.length != 4) throw const FormatException('Invalid uint32 field.');
    return ByteData.sublistView(
      Uint8List.fromList(bytes),
    ).getUint32(0, Endian.big);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
