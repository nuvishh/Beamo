import 'package:flutter/material.dart';

import '../models/transfer.dart';

/// Progress row for one file transfer (both directions).
class TransferTile extends StatelessWidget {
  final TransferInfo info;

  const TransferTile({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final isActive = info.status == TransferStatus.inProgress ||
        info.status == TransferStatus.waitingAccept ||
        info.status == TransferStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  info.direction == TransferDirection.sending
                      ? Icons.upload_file
                      : Icons.download_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.filename,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(info.sizeLabel,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            if (isActive)
              LinearProgressIndicator(value: info.progress)
            else
              const SizedBox(height: 4),
            const SizedBox(height: 4),
            Text(
              '${info.direction == TransferDirection.sending ? 'To' : 'From'} '
              '${info.peerName} · ${info.statusLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (info.savedPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Saved: ${info.savedPath}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
