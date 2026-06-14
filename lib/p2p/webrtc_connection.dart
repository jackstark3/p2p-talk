import 'dart:async';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/constants.dart';

/// Encapsulates a WebRTC peer connection with a single DataChannel.
///
/// Handles creating offers/answers, local/remote SDP, ICE candidates,
/// and the DataChannel for text messaging.
class WebRTCConnection {
  final String peerId;
  final RTCPeerConnection _pc;
  RTCDataChannel? _dataChannel;
  RTCDataChannel? _remoteDataChannel;
  RTCSessionDescription? _localDescription;

  final _messageController = StreamController<String>.broadcast();
  final _iceCandidateController =
      StreamController<RTCIceCandidate>.broadcast();
  final _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _dataChannelStateController =
      StreamController<RTCDataChannelState?>.broadcast();

  WebRTCConnection({
    required this.peerId,
    required RTCPeerConnection pc,
    RTCDataChannel? dataChannel,
  })  : _pc = pc,
        _dataChannel = dataChannel;

  /// Creates a new WebRTC connection as the initiator (offerer).
  static Future<WebRTCConnection> createOffer({
    required String peerId,
    required SignalingCallback onIceCandidate,
  }) async {
    final pc = await createPeerConnection({'iceServers': AppConstants.iceServers});

    // Create data channel
    final dataChannel =
        await pc.createDataChannel('chat', RTCDataChannelInit());
    final conn = WebRTCConnection(peerId: peerId, pc: pc, dataChannel: dataChannel);

    conn._setupListeners(onIceCandidate);

    // Create offer
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    conn._localDescription = offer;

    return conn;
  }

  /// Creates a new WebRTC connection as the receiver (answerer).
  static Future<WebRTCConnection> createAnswer({
    required String peerId,
    required Map<String, dynamic> remoteSdp,
    required SignalingCallback onIceCandidate,
  }) async {
    final pc = await createPeerConnection({'iceServers': AppConstants.iceServers});
    final conn = WebRTCConnection(peerId: peerId, pc: pc);

    conn._setupListeners(onIceCandidate);

    // Set remote offer
    await pc.setRemoteDescription(
      RTCSessionDescription(remoteSdp['sdp'], remoteSdp['type']),
    );

    // Create answer
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    conn._localDescription = answer;

    return conn;
  }

  void _setupListeners(SignalingCallback onIceCandidate) {
    // ICE candidates
    _pc.onIceCandidate = (candidate) {
      onIceCandidate(peerId, candidate);
    };

    // Connection state
    _pc.onConnectionState = (state) {
      _connectionStateController.add(state);
    };

    // Remote data channel — set BEFORE setRemoteDescription
    _pc.onDataChannel = (channel) {
      _remoteDataChannel = channel;
      _setupDataChannel(channel);
      _connLog('remote DataChannel received, state=${channel.state}');
    };

    // Local data channel — set up immediately
    if (_dataChannel != null) {
      _setupDataChannel(_dataChannel!);
      _connLog('local DataChannel set up, state=${_dataChannel!.state}');
    }
  }

  void _connLog(String msg) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      File('$exeDir\\p2p_talk_error.log').writeAsStringSync(
        '[${DateTime.now()}] WC: $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _connLog('_setupDataChannel state=${channel.state}, label=${channel.label}');
    channel.onMessage = (message) {
      _connLog('onMessage received: ${message.text.length} chars');
      _messageController.add(message.text);
    };

    channel.onDataChannelState = (state) {
      _connLog('DataChannel state → $state');
      _dataChannelStateController.add(state);
    };
  }

  /// Accepts the remote SDP answer from the other peer.
  Future<void> acceptAnswer(Map<String, dynamic> remoteSdp) async {
    await _pc.setRemoteDescription(
      RTCSessionDescription(remoteSdp['sdp'], remoteSdp['type']),
    );
  }

  /// Adds a remote ICE candidate.
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    await _pc.addCandidate(
      RTCIceCandidate(candidate['candidate'], candidate['sdpMid'], candidate['sdpMLineIndex']),
    );
  }

  /// Sends a text message over the DataChannel.
  void sendMessage(String text) {
    final channel = _dataChannel ?? _remoteDataChannel;
    _connLog('sendMessage: local=${_dataChannel != null}, remote=${_remoteDataChannel != null}, channelState=${channel?.state}');
    if (channel != null && channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel.send(RTCDataChannelMessage(text));
    } else {
      throw StateError('DataChannel not open');
    }
  }

  /// Stream of incoming text messages.
  Stream<String> get messages => _messageController.stream;

  /// Current local SDP (offer or answer).
  RTCSessionDescription? get localDescription => _localDescription;

  /// Connection state stream.
  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Whether the DataChannel is open.
  bool get isOpen {
    final channel = _dataChannel ?? _remoteDataChannel;
    return channel?.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  /// Closes the connection and releases resources.
  Future<void> close() async {
    _dataChannel?.close();
    _remoteDataChannel?.close();
    await _pc.close();
    await _pc.dispose();
    _messageController.close();
    _iceCandidateController.close();
    _connectionStateController.close();
    _dataChannelStateController.close();
  }
}

typedef SignalingCallback = void Function(
    String peerId, RTCIceCandidate candidate);
