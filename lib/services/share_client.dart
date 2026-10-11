import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/peer_device.dart';
import '../models/transfer.dart';

/// HTTP client used by the SENDER.
///
/// Flow per file: `POST /offer` -> poll `GET /offer/<id>/status` until
/// accepted/declined -> `POST /upload/<id>` with raw bytes.
class ShareClient {
  final http.Client _client = http.Client();

  void dispose() => _client.close();

  String _base(PeerDevice peer) => 'http://${peer.host}:${peer.port}';

  /// Quick liveness check (used for manual-IP connect).
  Future<bool> ping(PeerDevice peer) async {
    try {
      final r = await _client
          .get(Uri.parse('${_base(peer)}/ping'))
          .timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendFile({
    required PeerDevice peer,
    required File file,
    required String senderName,
    required void Function(TransferInfo info) onUpdate,
    Duration acceptTimeout = const Duration(seconds: 90),
  }) async {
    final filename = file.path.split(Platform.pathSeparator).last;
    final size = await file.length();
    final info = TransferInfo(
      id: const Uuid().v4(),
      filename: filename,
      size: size,
      peerName: peer.name,
      direction: TransferDirection.sending,
    );
    onUpdate(info);

    // 1. Offer
    http.Response offerRes;
    try {
      offerRes = await _client
          .post(
            Uri.parse('${_base(peer)}/offer'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'filename': filename,
              'size': size,
              'senderName': senderName,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      info.status = TransferStatus.failed;
      info.error = 'No response from ${peer.name}';
      onUpdate(info);
      return;
    }
    if (offerRes.statusCode != 200) {
      info.status = TransferStatus.failed;
      info.error = 'Offer rejected (HTTP ${offerRes.statusCode})';
      onUpdate(info);
      return;
    }
    final offerId =
        (jsonDecode(offerRes.body) as Map<String, dynamic>)['id'] as String;

    // 2. Wait for the receiver to accept.
    info.status = TransferStatus.waitingAccept;
    onUpdate(info);
    final accepted = await _waitForAccept(peer, offerId, acceptTimeout);
    if (!accepted) {
      info.status = TransferStatus.declined;
      onUpdate(info);
      return;
    }

    // 3. Upload raw bytes with progress.
    info.status = TransferStatus.inProgress;
    onUpdate(info);
    try {
      final req = http.StreamedRequest(
        'POST',
        Uri.parse('${_base(peer)}/upload/$offerId'),
      );
      req.headers['content-type'] = 'application/octet-stream';
      req.contentLength = size;

      var sent = 0;
      var lastUi = DateTime.now();
      unawaited(() async {
        try {
          await for (final chunk in file.openRead()) {
            req.sink.add(chunk);
            sent += chunk.length;
            info.progress = size > 0 ? sent / size : 0;
            if (DateTime.now().difference(lastUi).inMilliseconds > 250) {
              lastUi = DateTime.now();
              onUpdate(info);
            }
          }
          await req.sink.close();
        } catch (e) {
          req.sink.addError(e);
        }
      }());

      // Generous timeout scaled to file size (assumes >= ~256 KB/s).
      final streamed = await _client.send(req).timeout(
            Duration(seconds: 60 + (size ~/ (256 * 1024))),
          );
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}: $body');
      }
      info.status = TransferStatus.done;
      info.progress = 1.0;
      onUpdate(info);
    } catch (e) {
      info.status = TransferStatus.failed;
      info.error = e.toString().replaceFirst('Exception: ', '');
      onUpdate(info);
    }
  }

  Future<bool> _waitForAccept(
    PeerDevice peer,
    String offerId,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final r = await _client
            .get(Uri.parse('${_base(peer)}/offer/$offerId/status'))
            .timeout(const Duration(seconds: 5));
        if (r.statusCode == 200) {
          final status =
              (jsonDecode(r.body) as Map<String, dynamic>)['status'];
          if (status == 'accepted' || status == 'uploading') return true;
          if (status == 'declined' || status == 'failed') return false;
        }
      } catch (_) {
        // transient — keep polling
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}
