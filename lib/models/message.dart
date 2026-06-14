/// Status of a sent message.
enum MessageStatus {
  pending,   // queued locally, not yet sent
  sent,      // sent over DataChannel, awaiting ack
  delivered, // acknowledged by receiver
  read,      // read by receiver (future)
  failed,    // delivery failed after max retries
}

/// Data model for a chat message.
class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String ciphertext; // base64-encoded AES-GCM output
  final String? plaintext; // decrypted locally (not persisted in plaintext)
  final int timestamp; // Unix milliseconds
  final int seq; // session sequence number
  final MessageStatus status;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.ciphertext,
    this.plaintext,
    required this.timestamp,
    required this.seq,
    this.status = MessageStatus.pending,
  });

  Message copyWith({
    String? plaintext,
    MessageStatus? status,
  }) {
    return Message(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      ciphertext: ciphertext,
      plaintext: plaintext ?? this.plaintext,
      timestamp: timestamp,
      seq: seq,
      status: status ?? this.status,
    );
  }

  /// Whether this message was sent by us.
  bool get isOutgoing => status == MessageStatus.pending ||
      status == MessageStatus.sent ||
      status == MessageStatus.delivered ||
      status == MessageStatus.read;

  @override
  String toString() =>
      'Message(id=$id, seq=$seq, status=$status, ts=$timestamp)';
}
