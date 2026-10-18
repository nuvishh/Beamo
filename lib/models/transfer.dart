enum TransferDirection { sending, receiving }

enum TransferStatus {
  pending,
  waitingAccept,
  declined,
  inProgress,
  done,
  failed,
}

enum TransferKind { file, text }

/// Mutable transfer state. The services mutate [progress]/[status] and call
/// the UI callback; the UI just calls setState.
class TransferInfo {
  final String id;
  final String filename;
  final int size;
  final String peerName;
  final TransferDirection direction;
  final TransferKind kind;
  TransferStatus status;
  double progress;
  double speedBps;
  int? etaSeconds;
  String? savedPath;
  String? error;

  TransferInfo({
    required this.id,
    required this.filename,
    required this.size,
    required this.peerName,
    required this.direction,
    this.kind = TransferKind.file,
    this.status = TransferStatus.pending,
    this.progress = 0,
    this.speedBps = 0,
    this.etaSeconds,
    this.savedPath,
    this.error,
  });

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get speedLabel {
    if (speedBps < 1024) return '${speedBps.toStringAsFixed(0)} B/s';
    if (speedBps < 1024 * 1024) {
      return '${(speedBps / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speedBps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get etaLabel {
    final s = etaSeconds;
    if (s == null) return '';
    if (s < 60) return '$s s left';
    final m = s ~/ 60;
    return '${m}m ${s % 60}s left';
  }

  String get statusLabel {
    switch (status) {
      case TransferStatus.pending:
        return 'Preparing…';
      case TransferStatus.waitingAccept:
        return 'Waiting for $peerName to accept…';
      case TransferStatus.declined:
        return 'Declined';
      case TransferStatus.inProgress:
        return '${(progress * 100).toStringAsFixed(0)}%';
      case TransferStatus.done:
        return 'Done ✓';
      case TransferStatus.failed:
        return 'Failed${error != null ? ': $error' : ''}';
    }
  }
}
