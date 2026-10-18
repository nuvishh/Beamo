import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/peer_device.dart';
import '../theme/app_theme.dart';

/// Full-screen QR scanner. Expects a Beamo pairing code:
/// {"v":1,"name":"...","host":"192.168.x.x","port":8080}
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['v'] != 1 || m['host'] == null) {
        setState(() => _error = 'Not a Beamo code — try again.');
        return;
      }
      _done = true;
      final host = m['host'].toString();
      Navigator.of(context).pop(
        PeerDevice(
          name: (m['name']?.toString().isNotEmpty ?? false)
              ? m['name'].toString()
              : host,
          host: host,
          port: (m['port'] as num?)?.toInt() ?? 8080,
        ),
      );
    } catch (_) {
      setState(() => _error = 'Could not read that code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receiver QR')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          // Viewfinder frame
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.beamCyan, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Column(
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12, left: 32, right: 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.beamRose.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.beamRose.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: AppTheme.beamRose, fontSize: 13),
                    ),
                  ),
                const Text(
                  'Point at the QR shown on the receiver',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
