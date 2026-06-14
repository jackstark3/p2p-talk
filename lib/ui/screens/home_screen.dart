import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/avatar.dart';
import '../../models/contact.dart';
import '../../p2p/connection_manager.dart';
import '../../services/chat_service.dart';
import '../../services/contact_service.dart';
import 'chat_screen.dart';
import 'add_contact_screen.dart';
import 'my_qr_screen.dart';

/// Main screen: contact list with online/offline status.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final contactService = context.watch<ContactService>();
    final contacts = contactService.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Talk'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyQRScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddContactScreen()),
            ),
          ),
        ],
      ),
      body: contacts.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (_, i) => _ContactTile(contact: contacts[i]),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No contacts yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add contacts via QR code or PeerId',
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddContactScreen()),
            ),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;

  const _ContactTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    final isConnected = contact.isOnline;

    return ListTile(
      leading: Stack(
        children: [
          AvatarGenerator.build(contact.nickname),
          if (isConnected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(contact.nickname),
      subtitle: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: isConnected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(isConnected ? 'Online' : 'Offline'),
          if (contact.isNearby) ...[
            const SizedBox(width: 8),
            const Icon(Icons.wifi, size: 14, color: Colors.blue),
            const Text(' Nearby', style: TextStyle(color: Colors.blue)),
          ],
        ],
      ),
      trailing: Text(
        contact.fingerprint,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey[500],
            ),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(peerId: contact.peerId),
          ),
        );
      },
      onLongPress: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Contact'),
            content: Text('Remove ${contact.nickname}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  context.read<ContactService>().removeContact(contact.peerId);
                  Navigator.pop(ctx);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
    );
  }
}
