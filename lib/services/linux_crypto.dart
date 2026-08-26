import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

/// Small OpenSSL EVP wrapper used only on Linux. The Flutter plugin
/// `cryptography_flutter` does not provide a Linux backend, which otherwise
/// makes the Dart implementation process a 100+ MiB model byte-by-byte.
class LinuxAesGcmBox {
  const LinuxAesGcmBox(this.cipherText, this.mac);

  final Uint8List cipherText;
  final Uint8List mac;
}

class LinuxOpenSslAesGcm {
  LinuxOpenSslAesGcm._(this._crypto, this._libc) {
    _ctxNew = _crypto.lookupFunction<_CtxNewNative, _CtxNew>('EVP_CIPHER_CTX_new');
    _ctxFree = _crypto.lookupFunction<_CtxFreeNative, _CtxFree>('EVP_CIPHER_CTX_free');
    _aes256Gcm = _crypto.lookupFunction<_CipherNative, _Cipher>('EVP_aes_256_gcm');
    _encryptInit = _crypto.lookupFunction<_InitNative, _Init>('EVP_EncryptInit_ex');
    _encryptUpdate = _crypto.lookupFunction<_UpdateNative, _Update>('EVP_EncryptUpdate');
    _encryptFinal = _crypto.lookupFunction<_FinalNative, _Final>('EVP_EncryptFinal_ex');
    _decryptInit = _crypto.lookupFunction<_InitNative, _Init>('EVP_DecryptInit_ex');
    _decryptUpdate = _crypto.lookupFunction<_UpdateNative, _Update>('EVP_DecryptUpdate');
    _decryptFinal = _crypto.lookupFunction<_FinalNative, _Final>('EVP_DecryptFinal_ex');
    _ctrl = _crypto.lookupFunction<_CtrlNative, _Ctrl>('EVP_CIPHER_CTX_ctrl');
    _calloc = _libc.lookupFunction<_CallocNative, _Calloc>('calloc');
    _free = _libc.lookupFunction<_FreeNative, _Free>('free');
  }

  static LinuxOpenSslAesGcm? tryOpen() {
    if (!Platform.isLinux) return null;
    try {
      final crypto = _openFirst(<String>['libcrypto.so.3', 'libcrypto.so']);
      final libc = _openFirst(<String>['libc.so.6', 'libc.so']);
      final backend = LinuxOpenSslAesGcm._(crypto, libc);
      // Force symbol resolution during startup so the service can cleanly
      // fall back to package:cryptography if this host lacks an EVP symbol.
      backend._aes256Gcm();
      return backend;
    } catch (_) {
      return null;
    }
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
    throw StateError('Unable to load native library: $lastError');
  }

  final ffi.DynamicLibrary _crypto;
  final ffi.DynamicLibrary _libc;
  late final _CtxNew _ctxNew;
  late final _CtxFree _ctxFree;
  late final _Cipher _aes256Gcm;
  late final _Init _encryptInit;
  late final _Update _encryptUpdate;
  late final _Final _encryptFinal;
  late final _Init _decryptInit;
  late final _Update _decryptUpdate;
  late final _Final _decryptFinal;
  late final _Ctrl _ctrl;
  late final _Calloc _calloc;
  late final _Free _free;

  static const _getTag = 0x10;
  static const _setTag = 0x11;
  static const _tagSize = 16;

  LinuxAesGcmBox encrypt(
    Uint8List clear,
    Uint8List key,
    Uint8List nonce,
  ) {
    final ctx = _ctxNew();
    final keyPtr = _copyIn(key);
    final noncePtr = _copyIn(nonce);
    final inputPtr = _copyIn(clear);
    final outputPtr = _allocateBytes(clear.length + _tagSize);
    final outputLength = _allocateInts(1);
    final tagPtr = _allocateBytes(_tagSize);
    try {
      _check(
        _encryptInit(ctx, _aes256Gcm(), ffi.nullptr, keyPtr, noncePtr),
        'EVP_EncryptInit_ex',
      );
      _check(
        _encryptUpdate(ctx, outputPtr, outputLength, inputPtr, clear.length),
        'EVP_EncryptUpdate',
      );
      final written = outputLength.value;
      _check(
        _encryptFinal(ctx, outputPtr.elementAt(written), outputLength),
        'EVP_EncryptFinal_ex',
      );
      _check(_ctrl(ctx, _getTag, _tagSize, tagPtr.cast()), 'GET_TAG');
      return LinuxAesGcmBox(
        Uint8List.fromList(outputPtr.asTypedList(clear.length)),
        Uint8List.fromList(tagPtr.asTypedList(_tagSize)),
      );
    } finally {
      _ctxFree(ctx);
      _release(keyPtr);
      _release(noncePtr);
      _release(inputPtr);
      _release(outputPtr);
      _release(outputLength);
      _release(tagPtr);
    }
  }

  Uint8List decrypt(
    Uint8List cipherText,
    Uint8List key,
    Uint8List nonce,
    Uint8List tag,
  ) {
    final ctx = _ctxNew();
    final keyPtr = _copyIn(key);
    final noncePtr = _copyIn(nonce);
    final inputPtr = _copyIn(cipherText);
    final outputPtr = _allocateBytes(cipherText.length + _tagSize);
    final outputLength = _allocateInts(1);
    final tagPtr = _copyIn(tag);
    try {
      _check(
        _decryptInit(ctx, _aes256Gcm(), ffi.nullptr, keyPtr, noncePtr),
        'EVP_DecryptInit_ex',
      );
      _check(
        _decryptUpdate(ctx, outputPtr, outputLength, inputPtr, cipherText.length),
        'EVP_DecryptUpdate',
      );
      _check(_ctrl(ctx, _setTag, _tagSize, tagPtr.cast()), 'SET_TAG');
      final written = outputLength.value;
      if (_decryptFinal(ctx, outputPtr.elementAt(written), outputLength) != 1) {
        throw const FormatException('AES-256-GCM authentication failed.');
      }
      return Uint8List.fromList(outputPtr.asTypedList(cipherText.length));
    } finally {
      _ctxFree(ctx);
      _release(keyPtr);
      _release(noncePtr);
      _release(inputPtr);
      _release(outputPtr);
      _release(outputLength);
      _release(tagPtr);
    }
  }

  ffi.Pointer<ffi.Uint8> _allocateBytes(int count) =>
      _calloc(count, ffi.sizeOf<ffi.Uint8>()).cast();

  ffi.Pointer<ffi.Int32> _allocateInts(int count) =>
      _calloc(count, ffi.sizeOf<ffi.Int32>()).cast();

  ffi.Pointer<ffi.Uint8> _copyIn(Uint8List bytes) {
    final pointer = _allocateBytes(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  void _release(ffi.Pointer<ffi.NativeType> pointer) => _free(pointer.cast());

  static void _check(int result, String operation) {
    if (result != 1) throw StateError('$operation failed.');
  }
}

typedef _CtxNewNative = ffi.Pointer<ffi.Void> Function();
typedef _CtxNew = ffi.Pointer<ffi.Void> Function();
typedef _CtxFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CtxFree = void Function(ffi.Pointer<ffi.Void>);
typedef _CipherNative = ffi.Pointer<ffi.Void> Function();
typedef _Cipher = ffi.Pointer<ffi.Void> Function();
typedef _InitNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
);
typedef _Init = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
);
typedef _UpdateNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
);
typedef _Update = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _FinalNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Int32>,
);
typedef _Final = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Int32>,
);
typedef _CtrlNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int32,
  ffi.Int32,
  ffi.Pointer<ffi.Void>,
);
typedef _Ctrl = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  ffi.Pointer<ffi.Void>,
);
typedef _CallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr, ffi.IntPtr);
typedef _Calloc = ffi.Pointer<ffi.Void> Function(int, int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _Free = void Function(ffi.Pointer<ffi.Void>);
