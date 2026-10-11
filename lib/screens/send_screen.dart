import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/peer_device.dart';
import '../models/transfer.dart';
import '../services/discovery_service.dart';
import '../services/share_client.dart';
import '../widgets/transfer_tile.dart';

/// SENDER side: pick files, discover a receiver, send with progress.
class SendScreen extends StatefulWidget {
  final String deviceName;
  const SendScreen({super.key, required this.deviceName});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _discovery = DiscoveryService();
  final _client = ShareClient();
  final _manualIpController = TextEditingController();

  StreamSubscription<List<PeerDevice>>? _peerSub;
  List<PeerDevice> _peers = [];
  PeerDevice? _selected;

  final List<PlatformFile> _files = [];
  final Map<String, TransferInfo> _transfers = {}; // key: filepath
  bool _scanning = true;
  bool _manualBusy = false;

  @override
  void initState() {
    super.initState();
    _peerSub = _discovery.peers.listen((peers) {
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _scanning = false;
        if (_selected != null && !peers.contains(_selected)) {
          _selected = null;
        }
      });
    });
    _discovery.startBrowsing();
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _discovery.stopBrowsing();
    _discovery.dispose();
    _client.dispose();
    _manualIpController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    setState(() {
      for (final f in files) {
        if (f.path != null && !_files.any((e) => e.path == f.path)) {
          _files.add(f);
        }
      }
    });
  }

  Future<void> _connectManual() async {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;
    setState(() => _manualBusy = true);
    final peer = PeerDevice(name: ip, host: ip, port: 8080);
    final ok = await _client.ping(peer);
    if (!mounted) return;
    setState(() => _manualBusy = false);
    if (ok) {
      setState(() {
        if (!_peers.contains(peer)) _peers = [..._peers, peer];
        _selected = peer;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to $ip ✓')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No Beamo receiver at $ip:8080. Is Receive mode open there?',
          ),
        ),
      );
    }
  }

  Future<void> _sendFile(PlatformFile pf) async {
    final peer = _selected;
    final path = pf.path;
    if (peer == null || path == null) return;
    final key = path;
    if (_transfers[key]?.status == TransferStatus.inProgress ||
        _transfers[key]?.status == TransferStatus.waitingAccept) {
      return; // already sending
    }
    await _client.sendFile(
      peer: peer,
      file: File(path),
      senderName: widget.deviceName,
      onUpdate: (info) {
        if (!mounted) return;
        setState(() => _transfers[key] = info);
      },
    );
  }

  Future<void> _sendAll() async {
    for (final f in _files) {
      await _sendFile(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _selected != null && _files.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('📤 Send files')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. files
          Row(
            children: [
              Text('Files', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                autofocus: true,
                onPressed: _pickFiles,
                icon: const Icon(Icons.add),
                label: const Text('Pick files'),
              ),
            ],
          ),
          if (_files.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No files picked yet. Tap "Pick files".'),
              ),
            ),
          for (final f in _files)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(_fmtSize(f.lengthSync() ?? 0)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.send),
                      tooltip: 'Send this file',
                      onPressed: _selected == null ? null : () => _sendFile(f),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _files.removeWhere((e) => e == f)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          // 2. devices
          Text('Receivers nearby',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_scanning)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Scanning local network…'),
                ]),
              ),
            ),
          for (final p in _peers)
            Card(
              color: _selected == p
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                leading: const Icon(Icons.tv_rounded),
                title: Text(p.name),
                subtitle: Text(p.address),
                trailing: _selected == p
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () => setState(() => _selected = p),
              ),
            ),
          if (!_scanning && _peers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No receivers found. Open "Receive files" on the other '
                  'device (same Wi-Fi / hotspot), or enter its IP below.',
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualIpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Manual IP (e.g. 192.168.43.1)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lan),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _manualBusy
                  ? const CircularProgressIndicator()
                  : FilledButton.tonal(
                      onPressed: _connectManual,
                      child: const Text('Connect'),
                    ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: canSend ? _sendAll : null,
            icon: const Icon(Icons.send_rounded),
            label: Text(_selected == null
                ? 'Select a receiver first'
                : 'Send ${_files.length} file(s) to ${_selected!.name}'),
          ),
          const SizedBox(height: 16),
          // 3. transfers
          if (_transfers.isNotEmpty) ...[
            Text('Transfers', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final t in _transfers.values) TransferTile(info: t),
          ],
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
