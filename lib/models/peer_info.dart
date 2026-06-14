import 'dart:typed_data';

/// Peer connection information discovered via mDNS or signaling.
class PeerInfo {
  final String peerId;
  final String? ip;
  final int? port;
  final Uint8List? publicKey;
  final bool isLocal;

  const PeerInfo({
    required this.peerId,
    this.ip,
    this.port,
    this.publicKey,
    this.isLocal = true,
  });
}
