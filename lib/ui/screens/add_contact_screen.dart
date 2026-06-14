import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/identity.dart';
import '../../services/contact_service.dart';

/// Screen for adding a contact by entering their PeerId.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _peerIdController = TextEditingController();
  final _nicknameController = TextEditingController();

  void _add() {
    final peerId = _peerIdController.text.trim();
    final nickname = _nicknameController.text.trim();

    if (peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a PeerId')),
      );
      return;
    }
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a nickname')),
      );
      return;
    }

    final contactService = context.read<ContactService>();
    final identity = context.read<Identity>();

    if (peerId == identity.peerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot add yourself')),
      );
      return;
    }

    if (contactService.getContact(peerId) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact already exists')),
      );
      return;
    }

    try {
      contactService.addByPeerId(peerId, nickname);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nickname ($peerId) added')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Contact')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _peerIdController,
              decoration: const InputDecoration(
                labelText: 'PeerId',
                hintText: 'p2p_...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.fingerprint),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'e.g. Alice',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Contact'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Scan QR code
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
            ),
          ],
        ),
      ),
    );
  }
}
