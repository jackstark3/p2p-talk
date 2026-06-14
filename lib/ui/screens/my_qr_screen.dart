import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/identity.dart';

class MyQRScreen extends StatelessWidget {
  const MyQRScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = context.read<Identity>();
    final publicJson = identity.toPublicJson();
    final qrData = jsonEncode(publicJson);

    return Scaffold(
      appBar: AppBar(title: const Text('My QR Code')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 24),
            Text(
              identity.peerId,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: identity.peerId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PeerId copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy PeerId'),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this QR code or PeerId with others',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
