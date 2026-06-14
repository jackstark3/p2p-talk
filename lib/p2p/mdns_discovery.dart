import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../core/constants.dart';
import '../models/peer_info.dart';

/// Discovers nearby peers on the same LAN via mDNS.
///
/// Broadcasts this peer's presence and listens for others advertising
/// the `_p2ptalk._tcp.local` service.
class MDNSDiscovery {
  final String peerId;
  final MDnsClient _client = MDnsClient();
  final _onPeerFound = StreamController<PeerInfo>.broadcast();
  final _onPeerLost = StreamController<String>.broadcast();

  MDNSDiscovery({required this.peerId});

  Stream<PeerInfo> get onPeerFound => _onPeerFound.stream;
  Stream<String> get onPeerLost => _onPeerLost.stream;

  /// Starts mDNS discovery.
  Future<void> start() async {
    await _client.start();

    // Listen for other peers
    _client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(AppConstants.mdnsServiceType),
      timeout: Duration(seconds: 0), // continuous
    ).listen((ptr) {
      // Resolve the service to get txt records (contains peerId)
      _resolveService(ptr);
    });

    // Advertise this peer
    // Note: multicast_dns on some platforms doesn't support advertising
    // For full support, platform-specific code may be needed.
  }

  Future<void> _resolveService(PtrResourceRecord ptr) async {
    try {
      final srv = await _client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )
          .first;

      final txt = await _client
          .lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName),
          )
          .first;

      // Extract peerId from TXT record
      final txtMap = <String, String>{};
      for (final entry in txt.text.split('\x00')) {
        final eq = entry.indexOf('=');
        if (eq > 0) {
          txtMap[entry.substring(0, eq)] = entry.substring(eq + 1);
        }
      }

      final discoveredPeerId = txtMap['peerId'];
      if (discoveredPeerId != null && discoveredPeerId != peerId) {
        // Resolve IP
        final addresses = await _client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        );

        await for (final addr in addresses) {
          _onPeerFound.add(PeerInfo(
            peerId: discoveredPeerId,
            ip: addr.address.address,
            port: srv.port,
            isLocal: true,
          ));
        }
      }
    } catch (_) {
      // Resolution failed, ignore
    }
  }

  /// Stops mDNS and releases resources.
  void stop() {
    _client.stop();
    _onPeerFound.close();
    _onPeerLost.close();
  }
}
