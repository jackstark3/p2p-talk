import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pointycastle/export.dart';

import '../core/crypto.dart';
import '../core/identity.dart';
import '../models/message.dart';
import 'signaling_client.dart';
import 'webrtc_connection.dart';

/// High-level manager for P2P connections.
class ConnectionManager {
  final Identity identity;
  final SignalingClient signaling;
  final String Function(String peerId) getPeerPublicKeyHex;

  final _connections = <String, WebRTCConnection>{};
  final _onMessage = StreamController<Message>.broadcast();
  final _onConnectionChange =
      StreamController<({String peerId, PeerConnectionState state})>.broadcast();

  ConnectionManager({
    required this.identity,
    required this.signaling,
    required this.getPeerPublicKeyHex,
  }) {
    _listenSignaling();
  }

  Stream<Message> get onMessage => _onMessage.stream;
  Stream<({String peerId, PeerConnectionState state})> get onConnectionChange =>
      _onConnectionChange.stream;

  /// Starts the signaling connection.
  Future<void> start() async {
    await signaling.connect();
  }

  void _connLog(String msg) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      File('$exeDir\\p2p_talk_error.log').writeAsStringSync(
        '[${DateTime.now()}] CM(${identity.peerId}): $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// Initiates a call to [targetPeerId].
  Future<void> call(String targetPeerId) async {
    _connLog('call → $targetPeerId');
    _onConnectionChange
        .add((peerId: targetPeerId, state: PeerConnectionState.connecting));

    final conn = await WebRTCConnection.createOffer(
      peerId: targetPeerId,
      onIceCandidate: (peerId, candidate) {
        signaling.sendIceCandidate(
          targetPeerId,
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      },
    );

    _registerConnection(targetPeerId, conn);

    // Send call with SDP offer
    signaling.call(targetPeerId, {
      'sdp': conn.localDescription!.sdp,
      'type': conn.localDescription!.type,
    });
  }

  /// Accepts an incoming call with the remote SDP.
  Future<void> accept(String fromPeerId, Map<String, dynamic> remoteSdp) async {
    _onConnectionChange
        .add((peerId: fromPeerId, state: PeerConnectionState.connecting));

    final conn = await WebRTCConnection.createAnswer(
      peerId: fromPeerId,
      remoteSdp: remoteSdp,
      onIceCandidate: (peerId, candidate) {
        signaling.sendIceCandidate(
          fromPeerId,
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      },
    );

    _registerConnection(fromPeerId, conn);

    // Send answer SDP
    signaling.accept(fromPeerId, {
      'sdp': conn.localDescription!.sdp,
      'type': conn.localDescription!.type,
    });
  }

  /// Sends an encrypted text message to [peerId].
  Future<Message> sendMessage(String peerId, String ciphertext) async {
    // Try DataChannel first, fall back to signaling relay
    final conn = _connections[peerId];
    if (conn != null && conn.isOpen) {
      try {
        final envelope = jsonEncode({
          'sender': identity.peerId,
          'ct': ciphertext,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        conn.sendMessage(envelope);
        _connLog('sent via DataChannel to $peerId');
        return Message(
          id: '',
          senderId: identity.peerId,
          receiverId: peerId,
          ciphertext: ciphertext,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          seq: 0,
          status: MessageStatus.sent,
        );
      } catch (_) {}
    }

    // Fallback: relay through signaling server (still E2EE encrypted)
    signaling.sendData(peerId, ciphertext);
    _connLog('sent via signaling relay to $peerId');
    return Message(
      id: '',
      senderId: identity.peerId,
      receiverId: peerId,
      ciphertext: ciphertext,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      seq: 0,
      status: MessageStatus.sent,
    );
  }

  // ---- E2EE key cache ----

  final _e2eeCache = <String, E2EE>{};

  /// Returns the cached E2EE session for [peerId], if any.
  E2EE? e2eeFor(String peerId) => _e2eeCache[peerId];

  /// Gets or creates an E2EE session for [peerId].
  Future<E2EE> getOrCreateE2EE(String peerId) async {
    if (_e2eeCache.containsKey(peerId)) return _e2eeCache[peerId]!;

    final peerPubKeyHex = getPeerPublicKeyHex(peerId);
    final peerPubBytes = Uint8List.fromList(List.generate(
        peerPubKeyHex.length ~/ 2,
        (i) => int.parse(
            peerPubKeyHex.substring(i * 2, i * 2 + 2), radix: 16)));

    final domain = ECDomainParameters('secp256r1');
    final e2ee = E2EE.derive(
      ourPrivateKey: identity.privateKey,
      peerPublicKey: ECPublicKey(
        domain.curve.decodePoint(peerPubBytes),
        domain,
      ),
    );

    _e2eeCache[peerId] = e2ee;
    return e2ee;
  }

  // ---- private helpers ----

  void _registerConnection(String peerId, WebRTCConnection conn) {
    _connections[peerId]?.close();
    _connections[peerId] = conn;
    _connLog('connection registered for $peerId');

    conn.messages.listen((text) {
      _connLog('data received from $peerId');
      _handleIncoming(peerId, text);
    });

    conn.connectionState.listen((state) {
      _connLog('conn state: $peerId → $state');
      final cs = _toState(state);
      _onConnectionChange.add((peerId: peerId, state: cs));
    });
  }

  void _handleIncoming(String peerId, String text) {
    try {
      final envelope = jsonDecode(text) as Map<String, dynamic>;
      _onMessage.add(Message(
        id: envelope['id'] ?? '',
        senderId: envelope['sender'] ?? peerId,
        receiverId: identity.peerId,
        ciphertext: envelope['ct'] ?? '',
        timestamp: envelope['ts'] ?? 0,
        seq: envelope['seq'] ?? 0,
        status: MessageStatus.delivered,
      ));
    } catch (_) {
      // Ignore malformed messages
    }
  }

  void _listenSignaling() {
    signaling.messages.listen((msg) async {
      final type = msg['type'] as String?;
      final from = msg['from'] as String?;

      switch (type) {
        case 'data':
          // Message relayed via signaling server
          if (from != null && msg['payload'] != null) {
            _onMessage.add(Message(
              id: '',
              senderId: from,
              receiverId: identity.peerId,
              ciphertext: msg['payload'] as String,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              seq: 0,
              status: MessageStatus.delivered,
            ));
          }
          break;
        case 'presence':
          final pid = msg['peer_id'] as String?;
          final status = msg['status'] as String?;
          if (pid != null && status != null) {
            // Log for debugging
            try {
              final logPath = '${File(Platform.resolvedExecutable).parent.path}\\p2p_talk_error.log';
              File(logPath).writeAsStringSync(
                '[${DateTime.now()}] Presence: $pid is $status\n',
                mode: FileMode.append,
              );
            } catch (_) {}
            _onConnectionChange.add((
              peerId: pid,
              state: status == 'online'
                  ? PeerConnectionState.connected
                  : PeerConnectionState.disconnected,
            ));
          }
          break;
        case 'call':
          _connLog('received call from $from');
          if (from != null && msg['sdp'] != null) {
            await accept(from, msg['sdp'] as Map<String, dynamic>);
          } else {
            _connLog('call missing from or sdp: from=$from, hasSdp=${msg['sdp'] != null}');
          }
          break;
        case 'accept':
          _connLog('received accept from $from');
          if (from != null && msg['sdp'] != null) {
            final conn = _connections[from];
            if (conn != null) {
              await conn.acceptAnswer(msg['sdp'] as Map<String, dynamic>);
            } else {
              _connLog('no connection for $from');
            }
          }
          break;
        case 'ice_candidate':
          _connLog('ICE from $from');
          if (from != null && msg['candidate'] != null) {
            final conn = _connections[from];
            if (conn != null) {
              await conn.addIceCandidate(msg['candidate'] as Map<String, dynamic>);
            }
          }
          break;
        case 'reject':
          if (from != null) {
            _onConnectionChange
                .add((peerId: from, state: PeerConnectionState.failed));
          }
          break;
      }
    });
  }

  PeerConnectionState _toState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return PeerConnectionState.connecting;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return PeerConnectionState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return PeerConnectionState.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return PeerConnectionState.failed;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return PeerConnectionState.idle;
    }
  }

  /// Whether currently connected to [peerId].
  bool isConnected(String peerId) {
    final conn = _connections[peerId];
    return conn != null && conn.isOpen;
  }

  Future<void> dispose() async {
    for (final conn in _connections.values) {
      await conn.close();
    }
    signaling.disconnect();
    _onMessage.close();
    _onConnectionChange.close();
  }
}

enum PeerConnectionState { idle, connecting, connected, disconnected, failed }
