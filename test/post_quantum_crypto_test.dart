import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naza_llamadart_gui/services/crypto_service.dart';
import 'package:naza_llamadart_gui/services/linux_oqs.dart';

void main() {
  test(
    'ML-KEM-768 envelope round trip when pinned liboqs is available',
    () async {
      final crypto = NazaCryptoService();
      if (!crypto.isPostQuantumAvailable) return;

      final pair = crypto.generatePostQuantumKeyPair();
      expect(pair.publicKey, hasLength(LinuxLibOqs.publicKeySize));
      expect(pair.secretKey, hasLength(LinuxLibOqs.secretKeySize));

      final clear = Uint8List.fromList(<int>[0, 1, 2, 3, 254, 255]);
      final envelope = await crypto.encryptBytesPostQuantum(
        clear,
        pair.publicKey,
      );
      final decrypted = await crypto.decryptBytesPostQuantum(
        envelope,
        pair.secretKey,
      );
      expect(decrypted, clear);

      final tampered = Uint8List.fromList(envelope);
      tampered[tampered.length - 1] ^= 1;
      await expectLater(
        crypto.decryptBytesPostQuantum(tampered, pair.secretKey),
        throwsA(anything),
      );

      pair.secretKey.fillRange(0, pair.secretKey.length, 0);
    },
  );

  test('post-quantum API fails closed without exactly liboqs 0.14.0', () {
    final crypto = NazaCryptoService();
    if (crypto.isPostQuantumAvailable) return;
    expect(crypto.generatePostQuantumKeyPair, throwsStateError);
  });
}
