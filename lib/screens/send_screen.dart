import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/peer_device.dart';
import '../models/transfer.dart';
import '../services/discovery_service.dart';
import '../services/share_client.dart';
import '../theme/app_theme.dart';
import '../widgets/file_type_helper.dart';
import '../widgets/transfer_tile.dart';

/// SENDER side: pick files, discover receivers with rich cards, and beam with live progress.
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
  bool _isSendingAll = false;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  void _startDiscovery() {
    setState(() => _scanning = true);
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

  void _restartDiscovery() {
    _peerSub?.cancel();
    _discovery.stopBrowsing();
    _startDiscovery();
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

  int _fileSize(PlatformFile f) {
    if (f.path == null) return 0;
    try {
      return File(f.path!).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  int get _totalSelectedBytes {
    return _files.fold<int>(0, (sum, f) => sum + _fileSize(f));
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
    if (_selected == null || _files.isEmpty) return;
    setState(() => _isSendingAll = true);
    for (final f in _files) {
      await _sendFile(f);
    }
    if (mounted) setState(() => _isSendingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _selected != null && _files.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan network',
            onPressed: _restartDiscovery,
          ),
        ],
      ),
      bottomNavigationBar: canSend
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                border: const Border(
                  top: BorderSide(color: AppTheme.borderDark),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: FilledButton.icon(
                  onPressed: _isSendingAll ? null : _sendAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.beamCyan,
                    foregroundColor: const Color(0xFF061826),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isSendingAll
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF061826),
                          ),
                        )
                      : const Icon(Icons.bolt_rounded, size: 22),
                  label: Text(
                    _isSendingAll
                        ? 'Sending files…'
                        : 'Beam ${_files.length} File(s) to ${_selected!.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        children: [
          // Section 1: Selected Files
          Row(
            children: [
              const Text(
                'Files to Beam',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (_files.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.beamCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_files.length} • ${FileTypeHelper.formatBytes(_totalSelectedBytes)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.beamCyan,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (_files.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _files.clear()),
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: AppTheme.beamRose, fontSize: 13),
                  ),
                ),
              TextButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Files'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.beamCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_files.isEmpty)
            InkWell(
              onTap: _pickFiles,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCardDark,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.beamCyan.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.beamCyan.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_rounded,
                        color: AppTheme.beamCyan,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Tap to pick files from device',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Photos, 4K Videos, APKs, Zip Archives & Documents',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (final f in _files)
                  _FileItemTile(
                    file: f,
                    size: _fileSize(f),
                    canSend: _selected != null,
                    onSend: () => _sendFile(f),
                    onRemove: () =>
                        setState(() => _files.removeWhere((e) => e == f)),
                  ),
              ],
            ),

          const SizedBox(height: 24),

          // Section 2: Receivers Nearby
          Row(
            children: [
              const Text(
                'Receivers Nearby',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (_scanning) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.beamCyan,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Scanning…',
                  style: TextStyle(fontSize: 12, color: AppTheme.beamCyan),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          if (!_scanning && _peers.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.tv_off_rounded,
                    size: 38,
                    color: AppTheme.textMuted,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No receivers discovered yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Make sure "Receive files" is open on the TV or phone, and both are on the same Wi-Fi / hotspot.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),

          for (final p in _peers)
            _PeerCard(
              peer: p,
              isSelected: _selected == p,
              onTap: () => setState(() => _selected = p),
            ),

          const SizedBox(height: 16),

          // Manual IP Connect Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtleDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CANNOT FIND RECEIVER? ENTER IP MANUALLY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIpController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          hintText: '192.168.x.x',
                          prefixIcon: Icon(Icons.lan_rounded, size: 20),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _manualBusy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : FilledButton.tonal(
                            onPressed: _connectManual,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.surfaceElevatedDark,
                              foregroundColor: AppTheme.beamCyan,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            child: const Text('Connect'),
                          ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 3: Transfers
          if (_transfers.isNotEmpty) ...[
            const Text(
              'Active Transfers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            for (final t in _transfers.values) TransferTile(info: t),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }
}

class _FileItemTile extends StatelessWidget {
  final PlatformFile file;
  final int size;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onRemove;

  const _FileItemTile({
    required this.file,
    required this.size,
    required this.canSend,
    required this.onSend,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final meta = FileTypeHelper.getMeta(file.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(meta.icon, color: meta.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  FileTypeHelper.formatBytes(size),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 18),
            color: canSend ? AppTheme.beamCyan : AppTheme.textMuted,
            tooltip: 'Send this file',
            onPressed: canSend ? onSend : null,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppTheme.textMuted,
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _PeerCard extends StatefulWidget {
  final PeerDevice peer;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeerCard({
    required this.peer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_PeerCard> createState() => _PeerCardState();
}

class _PeerCardState extends State<_PeerCard> {
  bool _isFocused = false;

  bool get _isTv =>
      widget.peer.name.toLowerCase().contains('tv') ||
      widget.peer.name.toLowerCase().contains('android');

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppTheme.beamCyan.withValues(alpha: 0.08)
              : AppTheme.surfaceCardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isSelected
                ? AppTheme.beamCyan
                : _isFocused
                    ? AppTheme.beamCyan.withValues(alpha: 0.7)
                    : AppTheme.borderDark,
            width: widget.isSelected || _isFocused ? 2 : 1,
          ),
          boxShadow: [
            if (widget.isSelected)
              BoxShadow(
                color: AppTheme.beamCyan.withValues(alpha: 0.2),
                blurRadius: 10,
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? AppTheme.beamCyan.withValues(alpha: 0.2)
                          : AppTheme.surfaceElevatedDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isTv ? Icons.tv_rounded : Icons.phone_android_rounded,
                      color: widget.isSelected
                          ? AppTheme.beamCyan
                          : AppTheme.textSecondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.peer.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: widget.isSelected
                                ? AppTheme.beamCyan
                                : AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.peer.address,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isSelected)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: AppTheme.beamCyan,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF071B2A),
                        size: 18,
                      ),
                    )
                  else
                    const Icon(
                      Icons.circle_outlined,
                      size: 20,
                      color: AppTheme.textMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
