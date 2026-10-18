import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/transfer.dart';
import '../services/discovery_service.dart';
import '../services/network_service.dart';
import '../services/share_server.dart';
import '../services/trusted_service.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/file_type_helper.dart';
import '../widgets/radar_pulse.dart';
import '../widgets/transfer_tile.dart';

/// RECEIVER side: runs the HTTP server, advertises via mDNS,
/// shows accept/decline prompts, and displays an animated radar beacon.
/// Optimized for TVs and phones alike.
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
  Set<String> _trustedIds = {};

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

    _trustedIds = await TrustedService.trustedIds();
    final server = ShareServer(
      deviceName: widget.deviceName,
      onOffer: _onOffer,
      onTransferUpdate: _onTransferUpdate,
      isTrusted: (id) => id != null && _trustedIds.contains(id),
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


  /// Shows a QR code the sender can scan to connect without discovery.
  void _showQrDialog() {
    final payload = jsonEncode({
      'v': 1,
      'name': widget.deviceName,
      'host': _ip ?? '',
      'port': _server?.port ?? 8080,
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan to connect'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'On the sender: Send files → scan this QR.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Called by the server when a sender offers a file or text.
  /// Trusted devices skip this entirely (auto-accepted server-side).
  /// Shows a high-contrast accept/decline dialog (D-pad friendly: Accept focused).
  Future<bool> _onOffer(IncomingOffer offer) {
    final completer = Completer<bool>();
    if (!mounted) {
      completer.complete(false);
      return completer.future;
    }

    final meta = FileTypeHelper.getMeta(offer.filename);
    var trustDevice = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppTheme.beamEmerald, width: 1.5),
          ),
          title: Row(
            children: [
              Icon(
                offer.isText
                    ? Icons.text_snippet_outlined
                    : Icons.download_rounded,
                color: AppTheme.beamEmerald,
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                offer.isText ? 'Incoming Note' : 'Incoming File',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.isText
                      ? '${offer.senderName} sent a note:'
                      : '${offer.senderName} wants to beam:',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                if (offer.isText)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        offer.text ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(meta.icon, color: meta.color, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                offer.filename,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                FileTypeHelper.formatBytes(offer.size),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (offer.senderId != null) ...[
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: trustDevice,
                    onChanged: (v) =>
                        setDialogState(() => trustDevice = v ?? false),
                    title: Text(
                      'Always accept from ${offer.senderName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (!completer.isCompleted) completer.complete(false);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textMuted,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              child: const Text('Decline'),
            ),
            FilledButton.icon(
              autofocus: true, // D-pad autofocused for TV remotes
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.beamEmerald,
                foregroundColor: const Color(0xFF042017),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                if (!completer.isCompleted) completer.complete(true);
                if (trustDevice && offer.senderId != null) {
                  TrustedService.addTrusted(offer.senderId!).then((_) async {
                    _trustedIds = await TrustedService.trustedIds();
                  });
                }
              },
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text(
                'Accept',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );

    // Auto-decline if timeout
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
    if (info.status == TransferStatus.done ||
        info.status == TransferStatus.failed) {
      HistoryService.add(HistoryRecord.fromTransfer(info));
    }
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
    final ipText = _ip ?? 'Detecting IP…';
    final portText = '${_server?.port ?? 8080}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'Show pairing QR',
            onPressed: _showQrDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // Beacon Visualizer Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0B2433), Color(0xFF101C2E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _error != null
                    ? AppTheme.beamRose.withValues(alpha: 0.5)
                    : AppTheme.beamEmerald.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                if (_starting) ...[
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppTheme.beamEmerald,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Starting Receiver Server…',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ] else if (_error != null) ...[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 52,
                    color: AppTheme.beamRose,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.beamRose,
                    ),
                  ),
                ] else ...[
                  // Animated radar ripple with central glowing beacon
                  RadarPulse(
                    size: 150,
                    pulseColor: AppTheme.beamEmerald,
                    animate: true,
                    centerChild: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppTheme.beamEmerald, Color(0xFF059669)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.beamEmerald.withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.wifi_tethering_rounded,
                          size: 34,
                          color: Color(0xFF042017),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.beamEmerald,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DISCOVERABLE ON NETWORK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppTheme.beamEmerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.deviceName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // IP Badge with copy
                  InkWell(
                    onTap: _ip != null
                        ? () {
                            Clipboard.setData(ClipboardData(text: _ip!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('IP copied!')),
                            );
                          }
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lan_rounded,
                            size: 16,
                            color: AppTheme.beamEmerald,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$ipText : $portText',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: AppTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'On your phone: Open Beamo → Send files → select this receiver.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Transfers section
          if (_transfers.isNotEmpty) ...[
            const Text(
              'Transfers History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            for (final t in _transfers) TransferTile(info: t),
          ] else if (!_starting && _error == null) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCardDark,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.inbox_rounded,
                    size: 38,
                    color: AppTheme.textMuted,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Ready to receive files',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Incoming files will appear here and prompt for acceptance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
