/// Application-wide constants.
class AppConstants {
  AppConstants._();

  /// Signaling server URL (WebSocket).
  static const String signalingServerUrl = 'ws://192.168.1.138:8080/ws';

  /// mDNS service type for LAN peer discovery.
  static const String mdnsServiceType = '_p2ptalk._tcp.local';

  /// STUN servers for NAT traversal (free, public).
  static const List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  /// Prefix for PeerId.
  static const String peerIdPrefix = 'p2p_';

  /// Max pending offline message lifetime.
  static const Duration maxMessageAge = Duration(days: 7);

  /// WebSocket reconnect backoff.
  static const Duration wsReconnectMin = Duration(seconds: 1);
  static const Duration wsReconnectMax = Duration(seconds: 30);

  /// Heartbeat interval for signaling connection.
  static const Duration heartbeatInterval = Duration(seconds: 30);
}
