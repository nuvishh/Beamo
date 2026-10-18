import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer.dart';

/// Persistent transfer history (last 100 entries).
class HistoryRecord {
  final String filename;
  final int size;
  final String peerName;
  final String direction; // 'sent' | 'received'
  final String kind; // 'file' | 'text'
  final String status; // 'done' | 'failed' | 'declined'
  final int timestamp; // epoch seconds
  final String? savedPath;

  HistoryRecord({
    required this.filename,
    required this.size,
    required this.peerName,
    required this.direction,
    required this.kind,
    required this.status,
    required this.timestamp,
    this.savedPath,
  });

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'size': size,
        'peerName': peerName,
        'direction': direction,
        'kind': kind,
        'status': status,
        'timestamp': timestamp,
        'savedPath': savedPath,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> j) => HistoryRecord(
        filename: (j['filename'] ?? 'file').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        peerName: (j['peerName'] ?? '?').toString(),
        direction: (j['direction'] ?? 'sent').toString(),
        kind: (j['kind'] ?? 'file').toString(),
        status: (j['status'] ?? 'done').toString(),
        timestamp: (j['timestamp'] as num?)?.toInt() ?? 0,
        savedPath: j['savedPath']?.toString(),
      );

  factory HistoryRecord.fromTransfer(TransferInfo t) => HistoryRecord(
        filename: t.filename,
        size: t.size,
        peerName: t.peerName,
        direction: t.direction == TransferDirection.sending ? 'sent' : 'received',
        kind: t.kind == TransferKind.text ? 'text' : 'file',
        status: t.status == TransferStatus.done ? 'done' : 'failed',
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        savedPath: t.savedPath,
      );
}

class HistoryService {
  static const _key = 'beamo_history_v1';
  static const _max = 100;

  static Future<List<HistoryRecord>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => HistoryRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(HistoryRecord record) async {
    final p = await SharedPreferences.getInstance();
    final records = await load();
    records.insert(0, record);
    while (records.length > _max) {
      records.removeLast();
    }
    await p.setString(
      _key,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
