import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/transfer.dart';
import '../services/discovery_service.dart';
import '../services/network_service.dart';
import '../services/share_server.dart';
import '../widgets/transfer_tile.dart';

/// RECEIVER side: runs the HTTP server, advertises via mDNS,
/// shows accept/decline prompts and transfer progress.
/// This is the screen to open on the TV.
class ReceiveScreen extends StatefulWidget {
  final String deviceName;
  const ReceiveScreen({super.key, required this.deviceName});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _discovery = DiscoveryService();
  ShareServer? _server;

  final List<TransferInfo> _transfers = [];
  String? _ip;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Location permission is needed on Android for Wi-Fi IP / mDNS.
    await Permission.locationWhenInUse.request();

    final ip = await NetworkService.getLocalIp();
    if (!mounted) return;
    setState(() => _ip = ip);

    final server = ShareServer(
      deviceName: widget.deviceName,
      onOffer: _onOffer,
      onTransferUpdate: _onTransferUpdate,
    );
    try {
      await server.start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Could not start server: $e';
      });
      return;
    }
    _server = server;
    await _discovery.startAdvertising(widget.deviceName, server.port);

    if (!mounted) return;
    setState(() => _starting = false);
  }

  /// Called by the server when a sender offers a file.
  /// Shows a blocking accept/decline dialog (TV-friendly: Accept focused).
  Future<bool> _onOffer(IncomingOffer offer) {
    final completer = Completer<bool>();
    if (!mounted) {
      completer.complete(false);
      return completer.future;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('📥 Incoming file'),
        content: Text(
          '${offer.senderName} wants to send:\n\n'
          '${offer.filename}\n'
          '${_fmtSize(offer.size)}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete(false);
            },
            child: const Text('Decline'),
          ),
          FilledButton(
            autofocus: true, // D-pad friendly on TV
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete(true);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    // Auto-decline if the user walks away.
    Future.delayed(const Duration(seconds: 90), () {
      if (!completer.isCompleted) {
        completer.complete(false);
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });
    return completer.future;
  }

  void _onTransferUpdate(TransferInfo info) {
    if (!mounted) return;
    setState(() {
      final i = _transfers.indexWhere((t) => t.id == info.id);
      if (i >= 0) {
        _transfers[i] = info;
      } else {
        _transfers.insert(0, info);
      }
    });
  }

  @override
  void dispose() {
    _server?.stop();
    _discovery.stopAdvertising();
    _discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📥 Receive files')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_starting) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Starting receiver…'),
                  ] else if (_error != null) ...[
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                  ] else ...[
                    const Icon(Icons.wifi_tethering,
                        size: 56, color: Colors.teal),
                    const SizedBox(height: 12),
                    Text(
                      'Waiting for files…',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This device is visible as "${widget.deviceName}"\n'
                      '${_ip ?? '…'}:${_server?.port ?? 8080}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'On the sender: open Beamo → Send files → pick this device.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_transfers.isNotEmpty) ...[
            Text('Transfers', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final t in _transfers) TransferTile(info: t),
          ] else if (!_starting && _error == null)
            Text(
              'Received files will appear here.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
