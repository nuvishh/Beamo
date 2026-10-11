enum TransferDirection { sending, receiving }

enum TransferStatus {
  pending,
  waitingAccept,
  declined,
  inProgress,
  done,
  failed,
}

/// Mutable transfer state. The services mutate [progress]/[status] and call
/// the UI callback; the UI just calls setState.
class TransferInfo {
  final String id;
  final String filename;
  final int size;
  final String peerName;
  final TransferDirection direction;
  TransferStatus status;
  double progress;
  String? savedPath;
  String? error;

  TransferInfo({
    required this.id,
    required this.filename,
    required this.size,
    required this.peerName,
    required this.direction,
    this.status = TransferStatus.pending,
    this.progress = 0,
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
