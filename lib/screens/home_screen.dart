import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/network_service.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Redesigned Home Screen with high-contrast cards, glowing badges,
/// network status pill, and TV D-pad navigation support.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController(text: 'My Device');
  String? _ip;

  @override
  void initState() {
    super.initState();
    _nameController.text = NetworkService.defaultDeviceName();
    _refreshNetwork();
  }

  void _refreshNetwork() {
    NetworkService.getLocalIp().then((ip) {
      if (mounted) setState(() => _ip = ip);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _deviceName {
    final t = _nameController.text.trim();
    return t.isEmpty ? NetworkService.defaultDeviceName() : t;
  }

  void _showNameDialog() {
    final tempController = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: TextField(
          controller: tempController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            hintText: 'e.g. Living Room TV, Pixel 8',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = tempController.text.trim();
              if (newName.isNotEmpty) {
                setState(() => _nameController.text = newName);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _ip != null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            // Top App Bar & Status Pill
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppTheme.beamGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.beamCyan.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.cell_tower_rounded,
                      color: Color(0xFF071926),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'BEAMO',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Fast Local File Beam',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Network badge
                InkWell(
                  onTap: _refreshNetwork,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? AppTheme.beamEmerald.withValues(alpha: 0.12)
                          : AppTheme.beamAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isOnline
                            ? AppTheme.beamEmerald.withValues(alpha: 0.4)
                            : AppTheme.beamAmber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline
                                ? AppTheme.beamEmerald
                                : AppTheme.beamAmber,
                            boxShadow: [
                              BoxShadow(
                                color: (isOnline
                                        ? AppTheme.beamEmerald
                                        : AppTheme.beamAmber)
                                    .withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? 'Wi-Fi Ready' : 'Scanning…',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isOnline
                                ? AppTheme.beamEmerald
                                : AppTheme.beamAmber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Device Identity Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCardDark,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevatedDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.devices_rounded,
                      color: AppTheme.beamCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR DEVICE NAME',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    tooltip: 'Change device name',
                    onPressed: _showNameDialog,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Role Card 1: SEND FILES
            _HeroRoleCard(
              title: 'Send files',
              subtitle: 'Pick photos, videos, APKs or documents and beam them to TV or phone.',
              badgeText: 'SENDER MODE',
              badgeColor: AppTheme.beamCyan,
              icon: Icons.upload_file_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF0F2B48), Color(0xFF131D36)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              accentColor: AppTheme.beamCyan,
              autofocus: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SendScreen(deviceName: _deviceName),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Role Card 2: RECEIVE FILES
            _HeroRoleCard(
              title: 'Receive files',
              subtitle: 'Make this device discoverable on your Wi-Fi network. Autofocused for D-pad.',
              badgeText: '📺 IDEAL FOR ANDROID TV',
              badgeColor: AppTheme.beamEmerald,
              icon: Icons.download_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF0A332C), Color(0xFF112435)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              accentColor: AppTheme.beamEmerald,
              autofocus: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReceiveScreen(deviceName: _deviceName),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // History button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('Transfer history & trusted devices'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.borderDark),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 26),

            // Network Details & Hotspot Tip
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderSubtleDark),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wifi_rounded,
                        size: 18,
                        color: AppTheme.beamCyan,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _ip != null
                              ? 'Local IP: $_ip  •  Port: 8080'
                              : 'Searching Wi-Fi connection…',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (_ip != null)
                        IconButton(
                          icon: const Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                          tooltip: 'Copy IP',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _ip!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('IP copied to clipboard!'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: AppTheme.borderSubtleDark, height: 1),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'No internet needed. Works completely offline on the same Wi-Fi or phone hotspot.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroRoleCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final IconData icon;
  final LinearGradient gradient;
  final Color accentColor;
  final VoidCallback onTap;
  final bool autofocus;

  const _HeroRoleCard({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    required this.icon,
    required this.gradient,
    required this.accentColor,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_HeroRoleCard> createState() => _HeroRoleCardState();
}

class _HeroRoleCardState extends State<_HeroRoleCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isFocused
                ? widget.accentColor
                : widget.accentColor.withValues(alpha: 0.35),
            width: _isFocused ? 2.5 : 1,
          ),
          boxShadow: [
            if (_isFocused)
              BoxShadow(
                color: widget.accentColor.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.badgeColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.badgeColor.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          widget.badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: widget.badgeColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Floating Icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: widget.accentColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 26,
                          color: widget.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Tap to start',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: widget.accentColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: widget.accentColor,
                      ),
                    ],
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
