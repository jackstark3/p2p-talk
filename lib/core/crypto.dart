import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// End-to-end encryption using ECDH (secp256r1) + AES-256-GCM.
class E2EE {
  final Uint8List _sharedKey;
  int _seq = 0;

  E2EE._(this._sharedKey);

  /// Derives shared key from our private key and peer's EC public key.
  factory E2EE.derive({
    required ECPrivateKey ourPrivateKey,
    required ECPublicKey peerPublicKey,
  }) {
    final sharedSecret = _ecdh(ourPrivateKey, peerPublicKey);
    final aesKey = _hkdfExpand(sharedSecret, 'p2p-talk-aes-key', 32);
    return E2EE._(aesKey);
  }

  Uint8List encrypt(Uint8List plaintext) {
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(_sharedKey), 128, nonce, Uint8List(0)),
    );
    final encrypted = cipher.process(plaintext);
    return Uint8List.fromList([...nonce, ...encrypted]);
  }

  Uint8List decrypt(Uint8List ciphertext) {
    if (ciphertext.length < 12 + 16) {
      throw ArgumentError('Ciphertext too short');
    }
    final nonce = ciphertext.sublist(0, 12);
    final encrypted = ciphertext.sublist(12);

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(_sharedKey), 128, nonce, Uint8List(0)),
    );
    return cipher.process(encrypted);
  }

  int nextSeq() => _seq++;
  int get currentSeq => _seq;
}

// ---- Helpers ----

Uint8List _ecdh(ECPrivateKey privateKey, ECPublicKey publicKey) {
  final Q = publicKey.Q;
  if (Q == null) throw ArgumentError('Public key point is null');
  final shared = Q * privateKey.d!;
  if (shared == null) throw ArgumentError('Shared point is null');
  final xCoord = shared.x;
  if (xCoord == null) throw ArgumentError('Shared point X is null');
  final xBytes = _bigIntToBytes(xCoord.toBigInteger()!, 32);
  return Uint8List.fromList(xBytes);
}

Uint8List _hkdfExpand(Uint8List keyMaterial, String info, int length) {
  final hmac = HMac(SHA256Digest(), 64);
  hmac.init(KeyParameter(keyMaterial));

  final infoBytes = Uint8List.fromList(info.codeUnits);
  final output = Uint8List(length);
  int offset = 0;
  int i = 1;

  while (offset < length) {
    hmac.update(
        Uint8List.fromList([...infoBytes, i]), 0, infoBytes.length + 1);
    final h = Uint8List(32);
    hmac.doFinal(h, 0);
    final toCopy = (length - offset).clamp(0, 32);
    output.setRange(offset, offset + toCopy, h.sublist(0, toCopy));
    offset += toCopy;
    i++;
  }
  return output;
}

Uint8List _randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

Uint8List _bigIntToBytes(BigInt n, int byteLen) {
  final hexStr = n.toRadixString(16).padLeft(byteLen * 2, '0');
  final result = Uint8List(byteLen);
  for (int i = 0; i < byteLen; i++) {
    result[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
