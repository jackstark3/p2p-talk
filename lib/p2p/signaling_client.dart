/// WebSocket signaling client for WebRTC connection setup.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';

enum SignalingState { disconnected, connecting, connected, registered }

class SignalingClient {
  final String peerId;
  final String serverUrl;

  WebSocketChannel? _channel;
  SignalingState _state = SignalingState.disconnected;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<SignalingState>.broadcast();

  SignalingClient({
    required this.peerId,
    this.serverUrl = AppConstants.signalingServerUrl,
  });

  SignalingState get state => _state;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<SignalingState> get stateChanges => _stateController.stream;

  /// Connects to the signaling server and registers this peer.
  Future<void> connect() async {
    if (_state == SignalingState.connecting ||
        _state == SignalingState.registered) return;

    _setState(SignalingState.connecting);

    try {
      final wsUrl = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(wsUrl);
      await _channel!.ready;

      // Register
      send({'type': 'register', 'peer_id': peerId});

      _setState(SignalingState.connected);

      // Handle incoming messages
      _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final type = msg['type'] as String?;

          if (type == 'registered') {
            _setState(SignalingState.registered);
            _reconnectAttempts = 0;
            _startHeartbeat();
          }

          _messageController.add(msg);
        },
        onError: (error) {
          _setState(SignalingState.disconnected);
          _onDisconnected();
        },
        onDone: () {
          _setState(SignalingState.disconnected);
          _onDisconnected();
        },
      );
    } catch (e) {
      _setState(SignalingState.disconnected);
      _onDisconnected();
    }
  }

  /// Sends encrypted data via signaling relay.
  void sendData(String targetPeerId, String payload) {
    send({'type': 'data', 'to': targetPeerId, 'payload': payload});
  }

  /// Sends an arbitrary signaling message.
  void send(Map<String, dynamic> msg) {
    if (_channel != null && _state != SignalingState.disconnected) {
      msg['from'] = peerId;
      _channel!.sink.add(jsonEncode(msg));
    }
  }

  /// Sends a call request with SDP to [targetPeerId].
  void call(String targetPeerId, Map<String, dynamic>? sdp) {
    send({
      'type': 'call',
      'to': targetPeerId,
      if (sdp != null) 'sdp': sdp,
    });
  }

  /// Accepts an incoming call, providing the local SDP.
  void accept(String targetPeerId, Map<String, dynamic> sdp) {
    send({'type': 'accept', 'to': targetPeerId, 'sdp': sdp});
  }

  /// Rejects an incoming call.
  void reject(String targetPeerId) {
    send({'type': 'reject', 'to': targetPeerId});
  }

  /// Forwards an ICE candidate to the remote peer.
  void sendIceCandidate(String targetPeerId, Map<String, dynamic> candidate) {
    send({'type': 'ice_candidate', 'to': targetPeerId, 'candidate': candidate});
  }

  /// Disconnects from the signaling server.
  void disconnect() {
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _setState(SignalingState.disconnected);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AppConstants.heartbeatInterval, (_) {
      send({'type': 'ping'});
    });
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    final delay = Duration(
      seconds: (AppConstants.wsReconnectMin.inSeconds *
              (1 << _reconnectAttempts))
          .clamp(
            AppConstants.wsReconnectMin.inSeconds,
            AppConstants.wsReconnectMax.inSeconds,
          ),
    );
    _reconnectAttempts++;
    Future.delayed(delay, connect);
  }

  void _setState(SignalingState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }
}
