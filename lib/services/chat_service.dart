import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/identity.dart';
import '../models/message.dart';
import '../p2p/connection_manager.dart';
import 'contact_service.dart';
import 'storage_service.dart';

class ChatService extends ChangeNotifier {
  final ConnectionManager _connectionMgr;
  final StorageService _storage;
  final Identity _identity;
  final ContactService _contactService;

  final _newMessageController = StreamController<Message>.broadcast();
  final _messageUpdateController = StreamController<Message>.broadcast();
  Timer? _retryTimer;

  ChatService({
    required ConnectionManager connectionMgr,
    required StorageService storage,
    required Identity identity,
    required ContactService contactService,
  })  : _connectionMgr = connectionMgr,
        _storage = storage,
        _identity = identity,
        _contactService = contactService {
    _connectionMgr.onMessage.listen(_onMessageReceived);
    _connectionMgr.onConnectionChange.listen(_onConnectionChange);
  }

  Stream<Message> get newMessages => _newMessageController.stream;
  Stream<Message> get messageUpdates => _messageUpdateController.stream;

  Future<Message> sendMessage(String peerId, String plaintext) async {
    final msgId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Try to encrypt (may fail if contact has placeholder key)
    String ciphertext;
    int seq = 0;
    try {
      final e2ee = await _connectionMgr.getOrCreateE2EE(peerId);
      final plainBytes = utf8.encode(plaintext);
      final encrypted = e2ee.encrypt(plainBytes);
      ciphertext = base64.encode(encrypted);
      seq = e2ee.nextSeq();
    } catch (_) {
      // No real key yet — store as plain base64 (transport DTLS still encrypts)
      ciphertext = base64.encode(utf8.encode(plaintext));
    }

    // Try to send via active WebRTC connection
    if (_connectionMgr.isConnected(peerId)) {
      try {
        await _connectionMgr.sendMessage(peerId, ciphertext);
        final msg = Message(
          id: msgId,
          senderId: _identity.peerId,
          receiverId: peerId,
          ciphertext: ciphertext,
          plaintext: plaintext,
          timestamp: now,
          seq: seq,
          status: MessageStatus.sent,
        );
        await _storage.saveMessage(msg, chatWith: peerId);
        _newMessageController.add(msg);
        notifyListeners();
        return msg;
      } catch (_) {
        // Send failed — save as pending
      }
    }

    // Queue as pending
    final msg = Message(
      id: msgId,
      senderId: _identity.peerId,
      receiverId: peerId,
      ciphertext: ciphertext,
      plaintext: plaintext,
      timestamp: now,
      seq: seq,
      status: MessageStatus.pending,
    );
    await _storage.saveMessage(msg, chatWith: peerId);
    _newMessageController.add(msg);
    notifyListeners();
    return msg;
  }

  Future<List<Message>> loadMessages(String peerId) async {
    final messages = await _storage.loadMessages(peerId);
    final e2ee = _connectionMgr.e2eeFor(peerId);
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].plaintext == null && messages[i].ciphertext.isNotEmpty) {
        String plain = messages[i].ciphertext;
        // Try AES-GCM decrypt first (if we have a key)
        if (e2ee != null) {
          try {
            final cipherBytes = base64.decode(messages[i].ciphertext);
            final plainBytes = e2ee.decrypt(Uint8List.fromList(cipherBytes));
            plain = utf8.decode(plainBytes);
            messages[i] = messages[i].copyWith(plaintext: plain);
            continue;
          } catch (_) {}
        }
        // Fallback: plain base64 → UTF-8 (no encryption)
        try {
          plain = utf8.decode(base64.decode(messages[i].ciphertext));
          messages[i] = messages[i].copyWith(plaintext: plain);
        } catch (_) {}
      }
    }
    return messages;
  }

  void _onMessageReceived(Message envelope) async {
    String plain = envelope.ciphertext;
    try {
      final e2ee = await _connectionMgr.getOrCreateE2EE(envelope.senderId);
      final cipherBytes = base64.decode(envelope.ciphertext);
      final plainBytes = e2ee.decrypt(Uint8List.fromList(cipherBytes));
      plain = utf8.decode(plainBytes);
    } catch (_) {
      // Try plain base64 decode
      try {
        plain = utf8.decode(base64.decode(envelope.ciphertext));
      } catch (_) {}
    }

    final decrypted = envelope.copyWith(plaintext: plain);
    await _storage.saveMessage(decrypted, chatWith: envelope.senderId);
    _newMessageController.add(decrypted);
    notifyListeners();
  }

  void _onConnectionChange(
    ({String peerId, PeerConnectionState state}) event,
  ) {
    if (event.state == PeerConnectionState.connected) {
      _retryPending(event.peerId);
    }
  }

  Future<void> _retryPending(String peerId) async {
    final pending = await _storage.loadPendingMessages(peerId);
    for (final msg in pending) {
      try {
        await _connectionMgr.sendMessage(peerId, msg.ciphertext);
        await _storage.updateMessageStatus(msg.id, MessageStatus.sent);
        _messageUpdateController.add(msg.copyWith(status: MessageStatus.sent));
        notifyListeners();
      } catch (_) {
        break;
      }
    }
  }

  void startRetryLoop() {
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final contacts = _contactService.contacts;
      for (final contact in contacts) {
        await _retryPending(contact.peerId);
      }
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    _newMessageController.close();
    _messageUpdateController.close();
  }
}
