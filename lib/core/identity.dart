import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/src/registry/registration.dart';
import 'package:pointycastle/src/registry/registry.dart' show registry;

/// Identity module: ECDSA key pair on secp256r1 for signing + ECDH.
///
/// On first run, an ECDSA key pair is generated. The public key hash
/// becomes the human-readable PeerId.
class Identity {
  Identity._({
    required this.peerId,
    required this.publicKey,
    required keyPair,
  }) : _keyPair = keyPair;

  final String peerId;
  final Uint8List publicKey;

  final AsymmetricKeyPair<PublicKey, PrivateKey> _keyPair;

  ECPrivateKey get privateKey => _keyPair.privateKey as ECPrivateKey;
  ECPublicKey get pubKeyObj => _keyPair.publicKey as ECPublicKey;

  static const _domain = 'secp256r1';

  // ---- factory: generate a fresh identity ----

  factory Identity.generate() {
    registerFactories(registry);

    final kp = _generateECKeyPair();
    final pubBytes = (kp.publicKey as ECPublicKey).Q!
        .getEncoded(false); // includes 0x04 prefix (65 bytes for secp256r1)

    final peerId = _derivePeerId(pubBytes);

    return Identity._(
      peerId: peerId,
      publicKey: pubBytes,
      keyPair: kp,
    );
  }

  /// Reconstructs identity from stored hex keys.
  factory Identity.fromStorage({
    required String peerId,
    required String publicHex,
    required String privateHex,
  }) {
    registerFactories(registry);

    final domain = ECDomainParameters(_domain);
    final privD = BigInt.parse(privateHex, radix: 16);
    final pubBytes = hex.decode(publicHex);

    final priv = ECPrivateKey(privD, domain);
    final pub = ECPublicKey(domain.curve.decodePoint(pubBytes), domain);
    final kp = AsymmetricKeyPair<PublicKey, PrivateKey>(pub, priv);

    return Identity._(
      peerId: peerId,
      publicKey: Uint8List.fromList(pubBytes),
      keyPair: kp,
    );
  }

  // ---- serialization ----

  Map<String, dynamic> toPublicJson() => {
        'peer_id': peerId,
        'public_key': base64.encode(publicKey),
      };

  Map<String, String> toStorage() {
    final d = privateKey.d!;
    return {
      'peer_id': peerId,
      'public_hex': hex.encode(publicKey),
      'private_hex': _bigIntToHex(d, 32),
    };
  }

  // ---- signing (ECDSA) ----

  Uint8List sign(Uint8List data) {
    final signer = Signer('SHA-256/ECDSA');
    signer.init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
    final sig = signer.generateSignature(data) as ECSignature;
    final rBytes = _bigIntToBytes(sig.r, 32);
    final sBytes = _bigIntToBytes(sig.s, 32);
    return Uint8List.fromList([...rBytes, ...sBytes]);
  }

  bool verify(Uint8List data, Uint8List signature) {
    if (signature.length != 64) return false;
    final r = _bytesToBigInt(signature.sublist(0, 32));
    final s = _bytesToBigInt(signature.sublist(32));
    final verifier = Signer('SHA-256/ECDSA');
    verifier.init(false, PublicKeyParameter<ECPublicKey>(pubKeyObj));
    try {
      return verifier.verifySignature(data, ECSignature(r, s));
    } catch (_) {
      return false;
    }
  }

  // ---- helpers ----

  static AsymmetricKeyPair<PublicKey, PrivateKey> _generateECKeyPair() {
    final keyGen = KeyGenerator('EC');
    keyGen.init(ParametersWithRandom(
      ECKeyGeneratorParameters(ECDomainParameters(_domain)),
      _secureRandom(),
    ));
    return keyGen.generateKeyPair();
  }

  static SecureRandom _secureRandom() {
    final rng = FortunaRandom();
    final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    rng.seed(KeyParameter(Uint8List.fromList(seed)));
    return rng;
  }

  static String _derivePeerId(Uint8List pubBytes) {
    final hash = SHA256Digest().process(pubBytes);
    final hexStr = hex.encode(hash);
    return 'p2p_${hexStr.substring(0, 16)}';
  }

  static String _bigIntToHex(BigInt n, int byteLen) {
    return n.toRadixString(16).padLeft(byteLen * 2, '0');
  }

  static Uint8List _bigIntToBytes(BigInt n, int byteLen) {
    return Uint8List.fromList(hex.decode(_bigIntToHex(n, byteLen)));
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    return BigInt.parse(hex.encode(bytes), radix: 16);
  }
}
