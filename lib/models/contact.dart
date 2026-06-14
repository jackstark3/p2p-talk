import 'dart:typed_data';

/// Data model for a contact (peer).
class Contact {
  final String peerId;
  final String nickname;
  final Uint8List publicKey;
  final bool isOnline;
  final DateTime addedAt;
  final DateTime? lastSeen;
  final bool isNearby;

  const Contact({
    required this.peerId,
    required this.nickname,
    required this.publicKey,
    this.isOnline = false,
    required this.addedAt,
    this.lastSeen,
    this.isNearby = false,
  });

  Contact copyWith({
    String? nickname,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isNearby,
  }) {
    return Contact(
      peerId: peerId,
      nickname: nickname ?? this.nickname,
      publicKey: publicKey,
      isOnline: isOnline ?? this.isOnline,
      addedAt: addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isNearby: isNearby ?? this.isNearby,
    );
  }

  String get fingerprint {
    if (peerId.length <= 8) return peerId;
    return '${peerId.substring(0, 8)}...${peerId.substring(peerId.length - 4)}';
  }
}
