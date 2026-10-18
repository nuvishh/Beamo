import 'package:flutter/material.dart';

import '../services/history_service.dart';
import '../services/trusted_service.dart';
import '../theme/app_theme.dart';
import '../widgets/file_type_helper.dart';

/// Persistent transfer history + trusted-device management.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryRecord> _records = [];
  Set<String> _trusted = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final records = await HistoryService.load();
    final trusted = await TrustedService.trustedIds();
    if (!mounted) return;
    setState(() {
      _records = records;
      _trusted = trusted;
      _loading = false;
    });
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('All transfer records will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.beamRose,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await HistoryService.clear();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear history',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              children: [
                if (_trusted.isNotEmpty) ...[
                  const Text(
                    'TRUSTED DEVICES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final id in _trusted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              AppTheme.beamEmerald.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: AppTheme.beamEmerald,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Auto-accept enabled',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppTheme.textMuted,
                            tooltip: 'Remove trust',
                            onPressed: () async {
                              await TrustedService.removeTrusted(id);
                              _reload();
                            },
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'TRANSFERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (_records.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCardDark,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 40,
                          color: AppTheme.textMuted,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No transfers yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final r in _records) _HistoryTile(record: r),
              ],
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryRecord record;
  const _HistoryTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final meta = FileTypeHelper.getMeta(record.filename);
    final when = DateTime.fromMillisecondsSinceEpoch(record.timestamp * 1000);
    final date =
        '${when.day}/${when.month}/${when.year} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final ok = record.status == 'done';

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
            child: Icon(
              record.kind == 'text'
                  ? Icons.text_snippet_outlined
                  : meta.icon,
              color: meta.color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.filename,
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
                  '${record.direction == 'sent' ? 'To' : 'From'} ${record.peerName} • $date',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            size: 18,
            color: ok ? AppTheme.beamEmerald : AppTheme.beamRose,
          ),
        ],
      ),
    );
  }
}
