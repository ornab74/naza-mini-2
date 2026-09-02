import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

/// ML-KEM-768 bindings for the deliberately pinned liboqs 0.14.0 build.
///
/// The fixed sizes are the FIPS 203 ML-KEM-768 parameter sizes. Symbol and
/// runtime-version checks fail closed if an incompatible liboqs is present.
class MlKemKeyPair {
  const MlKemKeyPair(this.publicKey, this.secretKey);

  final Uint8List publicKey;
  final Uint8List secretKey;
}

class MlKemEncapsulation {
  const MlKemEncapsulation(this.ciphertext, this.sharedSecret);

  final Uint8List ciphertext;
  final Uint8List sharedSecret;
}

class LinuxLibOqs {
  LinuxLibOqs._(this._oqs, this._libc) {
    _version = _oqs.lookupFunction<_VersionNative, _Version>('OQS_version');
    _init = _oqs.lookupFunction<_InitNative, _Init>('OQS_init');
    _keypair = _oqs.lookupFunction<_KeypairNative, _Keypair>(
      'OQS_KEM_ml_kem_768_keypair',
    );
    _encaps = _oqs.lookupFunction<_EncapsNative, _Encaps>(
      'OQS_KEM_ml_kem_768_encaps',
    );
    _decaps = _oqs.lookupFunction<_DecapsNative, _Decaps>(
      'OQS_KEM_ml_kem_768_decaps',
    );
    _calloc = _libc.lookupFunction<_CallocNative, _Calloc>('calloc');
    _free = _libc.lookupFunction<_FreeNative, _Free>('free');
    _init();
    final actualVersion = _readCString(_version());
    if (actualVersion != requiredVersion) {
      throw StateError(
        'Refusing liboqs $actualVersion; NAZA requires exactly $requiredVersion.',
      );
    }
  }

  static const requiredVersion = '0.14.0';
  static const publicKeySize = 1184;
  static const secretKeySize = 2400;
  static const ciphertextSize = 1088;
  static const sharedSecretSize = 32;

  static LinuxLibOqs? tryOpen() {
    if (!Platform.isLinux) return null;
    try {
      final oqs = _openFirst(<String>[
        '${File(Platform.resolvedExecutable).parent.path}/lib/liboqs.so.8',
        'liboqs.so.8',
        'liboqs.so',
      ]);
      final libc = _openFirst(<String>['libc.so.6', 'libc.so']);
      return LinuxLibOqs._(oqs, libc);
    } catch (_) {
      return null;
    }
  }

  final ffi.DynamicLibrary _oqs;
  final ffi.DynamicLibrary _libc;
  late final _Version _version;
  late final _Init _init;
  late final _Keypair _keypair;
  late final _Encaps _encaps;
  late final _Decaps _decaps;
  late final _Calloc _calloc;
  late final _Free _free;

  MlKemKeyPair generateKeyPair() {
    final publicKey = _allocate(publicKeySize);
    final secretKey = _allocate(secretKeySize);
    try {
      _check(_keypair(publicKey, secretKey), 'ML-KEM-768 key generation');
      return MlKemKeyPair(
        _copyOut(publicKey, publicKeySize),
        _copyOut(secretKey, secretKeySize),
      );
    } finally {
      _release(publicKey, publicKeySize);
      _release(secretKey, secretKeySize);
    }
  }

  MlKemEncapsulation encapsulate(Uint8List publicKeyBytes) {
    _requireLength(publicKeyBytes, publicKeySize, 'public key');
    final publicKey = _copyIn(publicKeyBytes);
    final ciphertext = _allocate(ciphertextSize);
    final sharedSecret = _allocate(sharedSecretSize);
    try {
      _check(
        _encaps(ciphertext, sharedSecret, publicKey),
        'ML-KEM-768 encapsulation',
      );
      return MlKemEncapsulation(
        _copyOut(ciphertext, ciphertextSize),
        _copyOut(sharedSecret, sharedSecretSize),
      );
    } finally {
      _release(publicKey, publicKeySize);
      _release(ciphertext, ciphertextSize);
      _release(sharedSecret, sharedSecretSize);
    }
  }

  Uint8List decapsulate(Uint8List ciphertextBytes, Uint8List secretKeyBytes) {
    _requireLength(ciphertextBytes, ciphertextSize, 'ciphertext');
    _requireLength(secretKeyBytes, secretKeySize, 'secret key');
    final ciphertext = _copyIn(ciphertextBytes);
    final secretKey = _copyIn(secretKeyBytes);
    final sharedSecret = _allocate(sharedSecretSize);
    try {
      _check(
        _decaps(sharedSecret, ciphertext, secretKey),
        'ML-KEM-768 decapsulation',
      );
      return _copyOut(sharedSecret, sharedSecretSize);
    } finally {
      _release(ciphertext, ciphertextSize);
      _release(secretKey, secretKeySize);
      _release(sharedSecret, sharedSecretSize);
    }
  }

  ffi.Pointer<ffi.Uint8> _allocate(int count) =>
      _calloc(count, ffi.sizeOf<ffi.Uint8>()).cast();

  ffi.Pointer<ffi.Uint8> _copyIn(Uint8List bytes) {
    final result = _allocate(bytes.length);
    result.asTypedList(bytes.length).setAll(0, bytes);
    return result;
  }

  static Uint8List _copyOut(ffi.Pointer<ffi.Uint8> value, int count) =>
      Uint8List.fromList(value.asTypedList(count));

  void _release(ffi.Pointer<ffi.Uint8> value, int count) {
    value.asTypedList(count).fillRange(0, count, 0);
    _free(value.cast());
  }

  static void _requireLength(Uint8List value, int expected, String label) {
    if (value.length != expected) {
      throw ArgumentError('$label must be exactly $expected bytes.');
    }
  }

  static void _check(int status, String operation) {
    if (status != 0) throw StateError('$operation failed.');
  }

  static ffi.DynamicLibrary _openFirst(List<String> names) {
    Object? lastError;
    for (final name in names) {
      try {
        return ffi.DynamicLibrary.open(name);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Unable to load pinned liboqs: $lastError');
  }

  static String _readCString(ffi.Pointer<ffi.Char> pointer) {
    final bytes = <int>[];
    for (var i = 0; i < 64; i++) {
      final value = pointer.elementAt(i).value;
      if (value == 0) return String.fromCharCodes(bytes);
      bytes.add(value & 0xff);
    }
    throw const FormatException('Invalid liboqs version string.');
  }
}

typedef _VersionNative = ffi.Pointer<ffi.Char> Function();
typedef _Version = ffi.Pointer<ffi.Char> Function();
typedef _InitNative = ffi.Void Function();
typedef _Init = void Function();
typedef _KeypairNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>);
typedef _Keypair = int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>);
typedef _EncapsNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _Encaps =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _DecapsNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _Decaps =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _CallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr, ffi.IntPtr);
typedef _Calloc = ffi.Pointer<ffi.Void> Function(int, int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _Free = void Function(ffi.Pointer<ffi.Void>);
