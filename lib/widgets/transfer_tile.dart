import 'package:flutter/material.dart';

import '../models/transfer.dart';
import '../theme/app_theme.dart';
import 'file_type_helper.dart';

/// Modern progress card for active and completed file transfers.
class TransferTile extends StatelessWidget {
  final TransferInfo info;

  const TransferTile({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final meta = FileTypeHelper.getMeta(info.filename);
    final isSending = info.direction == TransferDirection.sending;
    final isActive = info.status == TransferStatus.inProgress ||
        info.status == TransferStatus.waitingAccept ||
        info.status == TransferStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppTheme.beamCyan.withValues(alpha: 0.35)
              : AppTheme.borderDark,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // File type icon container
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: meta.color.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 22),
                ),
                const SizedBox(width: 12),
                // File details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.filename,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            isSending
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 13,
                            color: isSending
                                ? AppTheme.beamCyan
                                : AppTheme.beamEmerald,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSending
                                ? 'To ${info.peerName}'
                                : 'From ${info.peerName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '•',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            info.sizeLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status badge
                _buildStatusBadge(context),
              ],
            ),
            if (isActive && info.status == TransferStatus.inProgress) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: info.progress,
                  minHeight: 6,
                  backgroundColor: AppTheme.surfaceDark,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.beamCyan,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.speed_rounded,
                    size: 12,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    info.speedLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Text(
                    info.etaLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
            if (info.savedPath != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_open_outlined,
                      size: 14,
                      color: AppTheme.beamEmerald,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Saved: ${info.savedPath}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    Color badgeColor;
    String label;
    IconData? badgeIcon;

    switch (info.status) {
      case TransferStatus.pending:
        badgeColor = AppTheme.textMuted;
        label = 'Pending';
        badgeIcon = Icons.hourglass_top_rounded;
        break;
      case TransferStatus.waitingAccept:
        badgeColor = AppTheme.beamAmber;
        label = 'Waiting';
        badgeIcon = Icons.pan_tool_outlined;
        break;
      case TransferStatus.declined:
        badgeColor = AppTheme.beamRose;
        label = 'Declined';
        badgeIcon = Icons.cancel_outlined;
        break;
      case TransferStatus.inProgress:
        badgeColor = AppTheme.beamCyan;
        label = '${(info.progress * 100).toStringAsFixed(0)}%';
        badgeIcon = Icons.bolt_rounded;
        break;
      case TransferStatus.done:
        badgeColor = AppTheme.beamEmerald;
        label = 'Done';
        badgeIcon = Icons.check_circle_outline_rounded;
        break;
      case TransferStatus.failed:
        badgeColor = AppTheme.beamRose;
        label = 'Failed';
        badgeIcon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 12, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
