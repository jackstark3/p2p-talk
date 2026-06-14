import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/identity.dart';
import '../../p2p/signaling_client.dart';

/// Settings screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = context.read<Identity>();
    final signaling = context.read<SignalingClient>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Identity'),
          ListTile(
            title: const Text('Peer ID'),
            subtitle: Text(identity.peerId),
            leading: const Icon(Icons.fingerprint),
          ),
          ListTile(
            title: const Text('Public Key Fingerprint'),
            subtitle: Text(identity.peerId.length > 8
                ? '${identity.peerId.substring(0, 12)}...${identity.peerId.substring(identity.peerId.length - 8)}'
                : identity.peerId),
            leading: const Icon(Icons.key),
          ),
          const Divider(),
          _Section(title: 'Connection'),
          ListTile(
            title: const Text('Signaling Server'),
            subtitle: const Text('ws://localhost:8080/ws'),
            leading: const Icon(Icons.cloud),
            trailing: _statusChip(signaling.state.name),
          ),
          const Divider(),
          _Section(title: 'About'),
          const ListTile(
            title: Text('Version'),
            subtitle: Text('0.1.0'),
            leading: Icon(Icons.info),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label) {
    final color = label == 'registered' ? Colors.green : Colors.orange;
    return Chip(
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withOpacity(0.1),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
