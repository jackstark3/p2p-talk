import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/identity.dart';
import '../models/contact.dart';
import '../models/peer_info.dart';
import 'storage_service.dart';

String _myPeerId = 'unknown';
void _log(String msg) {
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    File('$exeDir\\p2p_talk_error.log').writeAsStringSync(
      '[${DateTime.now()}] CS($_myPeerId): $msg\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

/// Manages contacts: add, remove, list, and sync with mDNS discoveries.
class ContactService extends ChangeNotifier {
  final StorageService _storage;
  final Identity _identity;

  List<Contact> _contacts = [];
  final _onlinePeers = <String, bool>{}; // cache presence events
  final _contactsController = StreamController<List<Contact>>.broadcast();

  ContactService({
    required StorageService storage,
    required Identity identity,
  })  : _storage = storage,
        _identity = identity {
    _myPeerId = identity.peerId;
  }

  List<Contact> get contacts => List.unmodifiable(_contacts);
  Stream<List<Contact>> get contactsStream => _contactsController.stream;

  /// Adds a contact by PeerId + nickname (without public key).
  /// Real key exchange will happen on first P2P connection.
  Future<Contact> addByPeerId(String peerId, String nickname) async {
    _log('addByPeerId: $peerId, cache has: ${_onlinePeers.containsKey(peerId)}, value: ${_onlinePeers[peerId]}, all keys: ${_onlinePeers.keys.toList()}');
    if (peerId == _identity.peerId) {
      throw ArgumentError('Cannot add yourself');
    }

    final contact = Contact(
      peerId: peerId,
      nickname: nickname,
      publicKey: Uint8List(65),
      isOnline: _onlinePeers[peerId] ?? false,
      addedAt: DateTime.now(),
    );

    await _storage.saveContact(contact);
    _contacts.removeWhere((c) => c.peerId == peerId);
    _contacts.insert(0, contact);
    _contactsController.add(_contacts);
    notifyListeners();

    // Re-check after delay — presence may have been a late arrival
    Future.delayed(const Duration(seconds: 3), () {
      if (_onlinePeers.containsKey(peerId) && _onlinePeers[peerId] == true) {
        updateOnlineStatus(peerId, true);
      }
    });

    return contact;
  }

  Future<void> load() async {
    _contacts = await _storage.loadContacts();
    _log('load: ${_contacts.length} contacts loaded, online peers cached: ${_onlinePeers.length}');
    // Apply cached online status from presence events
    for (int i = 0; i < _contacts.length; i++) {
      if (_onlinePeers.containsKey(_contacts[i].peerId)) {
        _contacts[i] = _contacts[i].copyWith(isOnline: _onlinePeers[_contacts[i].peerId]!);
      }
    }
    _contactsController.add(_contacts);
    notifyListeners();
  }

  Future<Contact> addContact({
    required Map<String, dynamic> publicIdentity,
    required String nickname,
  }) async {
    final peerId = publicIdentity['peer_id'] as String;
    if (peerId == _identity.peerId) {
      throw ArgumentError('Cannot add yourself');
    }

    final contact = Contact(
      peerId: peerId,
      nickname: nickname,
      publicKey: base64.decode(publicIdentity['public_key'] as String),
      addedAt: DateTime.now(),
    );

    await _storage.saveContact(contact);
    _contacts.removeWhere((c) => c.peerId == peerId);
    _contacts.insert(0, contact);
    _contactsController.add(_contacts);
    notifyListeners();

    return contact;
  }

  Future<Contact?> addFromMDNS(PeerInfo peerInfo) async {
    if (peerInfo.peerId == _identity.peerId) return null;

    final existing = _contacts.where((c) => c.peerId == peerInfo.peerId);
    if (existing.isNotEmpty) {
      final idx = _contacts.indexOf(existing.first);
      _contacts[idx] = existing.first.copyWith(isNearby: true);
      _contactsController.add(_contacts);
    notifyListeners();
      return _contacts[idx];
    }

    final contact = Contact(
      peerId: peerInfo.peerId,
      nickname: peerInfo.peerId,
      publicKey: Uint8List(65),
      addedAt: DateTime.now(),
      isNearby: true,
    );

    await _storage.saveContact(contact);
    _contacts.insert(0, contact);
    _contactsController.add(_contacts);
    notifyListeners();

    return contact;
  }

  Future<void> removeContact(String peerId) async {
    await _storage.deleteContact(peerId);
    _contacts.removeWhere((c) => c.peerId == peerId);
    _contactsController.add(_contacts);
    notifyListeners();
  }

  Future<void> updateOnlineStatus(String peerId, bool online) async {
    _log('updateOnlineStatus: $peerId online=$online (in contacts: ${_contacts.any((c) => c.peerId == peerId)})');
    _onlinePeers[peerId] = online;
    await _storage.updateContactOnline(peerId, online);
    final idx = _contacts.indexWhere((c) => c.peerId == peerId);
    if (idx >= 0) {
      _contacts[idx] = _contacts[idx].copyWith(
        isOnline: online,
        lastSeen: DateTime.now(),
      );
      _contactsController.add(_contacts);
      notifyListeners();
    }
  }

  bool isOnline(String peerId) => _onlinePeers[peerId] ?? false;

  Contact? getContact(String peerId) {
    try {
      return _contacts.firstWhere((c) => c.peerId == peerId);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _contactsController.close();
  }
}
