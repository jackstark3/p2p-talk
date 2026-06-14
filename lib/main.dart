import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/identity.dart';
import 'p2p/connection_manager.dart';
import 'p2p/mdns_discovery.dart';
import 'p2p/signaling_client.dart';
import 'services/chat_service.dart';
import 'services/contact_service.dart';
import 'services/storage_service.dart';
import 'ui/screens/home_screen.dart';

/// Profile name — set via command line `--profile=xxx` or defaults to "default".
String appProfile = 'default';

void main(List<String> args) async {
  // Parse --profile=xxx from command line
  for (final arg in args) {
    if (arg.startsWith('--profile=')) {
      appProfile = arg.split('=').last;
    }
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite for desktop
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Capture all errors to a log file that Claude can read
  FlutterError.onError = (details) {
    _logError('FlutterError', details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('Uncaught', error.toString());
    return true;
  };

  runApp(const P2PTalkApp());
}

String get _logPath {
  // Write log next to the exe
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  return '$exeDir\\p2p_talk_error.log';
}

void _logError(String type, String msg) {
  try {
    final f = File(_logPath);
    final ts = DateTime.now().toIso8601String();
    f.writeAsStringSync('[$ts] $type: $msg\n', mode: FileMode.append);
  } catch (_) {}
}

void _logInfo(String msg) {
  _logError('INFO', msg);
}

class P2PTalkApp extends StatefulWidget {
  const P2PTalkApp({super.key});

  @override
  State<P2PTalkApp> createState() => _P2PTalkAppState();
}

class _P2PTalkAppState extends State<P2PTalkApp> {
  late final StorageService _storage;
  late final Identity _identity;
  late final SignalingClient _signaling;
  late final ConnectionManager _connectionMgr;
  late final ContactService _contactService;
  late final ChatService _chatService;
  late final MDNSDiscovery _mdns;

  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _storage = StorageService(profile: appProfile);
      await _storage.db;

      Map<String, String>? storedKeys = await _storage.loadIdentity();

      if (storedKeys == null || storedKeys.isEmpty) {
        final id = Identity.generate();
        final keys = id.toStorage();
        await _storage.saveIdentity(keys);
        storedKeys = keys;
        _identity = id;
      } else {
        _identity = Identity.fromStorage(
          peerId: storedKeys['peer_id']!,
          publicHex: storedKeys['public_hex']!,
          privateHex: storedKeys['private_hex']!,
        );
      }

      _signaling = SignalingClient(peerId: _identity.peerId);

      _contactService = ContactService(
        storage: _storage,
        identity: _identity,
      );
      await _contactService.load();

      _connectionMgr = ConnectionManager(
        identity: _identity,
        signaling: _signaling,
        getPeerPublicKeyHex: (peerId) {
          final contact = _contactService.getContact(peerId);
          return contact != null ? _bytesToHex(contact.publicKey) : '';
        },
      );

      _chatService = ChatService(
        connectionMgr: _connectionMgr,
        storage: _storage,
        identity: _identity,
        contactService: _contactService,
      );
      _chatService.startRetryLoop();

      _mdns = MDNSDiscovery(peerId: _identity.peerId);
      _mdns.onPeerFound.listen((peerInfo) {
        _contactService.addFromMDNS(peerInfo);
      });
      try {
        await _mdns.start();
      } catch (e) {
        // mDNS may not work on some Windows versions — non-fatal
      }

      try {
        await _connectionMgr.start();
        _logError('Info', 'Signaling connected: ${_signaling.state.name}');
      } catch (e) {
        _logError('Signaling', 'Failed to connect: $e');
      }

      // Listen for presence updates to update contact online status
      _connectionMgr.onConnectionChange.listen((event) {
        final online = event.state == PeerConnectionState.connected;
        _contactService.updateOnlineStatus(event.peerId, online);
        // Also broadcast to chat service for connection retry
        if (online) {
          _logInfo('Peer online: ${event.peerId}');
        }
      });

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      _logError('Init', e.toString());
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(body: Center(child: Text('Init error: $_error'))),
      );
    }
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        Provider.value(value: _identity),
        ChangeNotifierProvider.value(value: _contactService),
        ChangeNotifierProvider.value(value: _chatService),
        Provider.value(value: _connectionMgr),
        Provider.value(value: _signaling),
        Provider.value(value: _mdns),
      ],
      child: MaterialApp(
        title: 'P2P Talk',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
