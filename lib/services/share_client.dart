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
/// Text shares skip the upload: the text rides inside the offer.
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
    String? senderId,
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
    final offerId = await _postOffer(
      peer: peer,
      info: info,
      onUpdate: onUpdate,
      body: {
        'filename': filename,
        'size': size,
        'senderName': senderName,
        if (senderId != null) 'senderId': senderId,
      },
    );
    if (offerId == null) return;

    // 2. Wait for the receiver to accept.
    info.status = TransferStatus.waitingAccept;
    onUpdate(info);
    final accepted = await _waitForAccept(peer, offerId, acceptTimeout);
    if (!accepted) {
      info.status = TransferStatus.declined;
      onUpdate(info);
      return;
    }

    // 3. Upload raw bytes with progress + speed.
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
      var windowStart = DateTime.now();
      var windowBytes = 0;
      unawaited(() async {
        try {
          await for (final chunk in file.openRead()) {
            req.sink.add(chunk);
            sent += chunk.length;
            windowBytes += chunk.length;
            info.progress = size > 0 ? sent / size : 0;

            final now = DateTime.now();
            final wMs = now.difference(windowStart).inMilliseconds;
            if (wMs >= 1000) {
              info.speedBps = windowBytes * 1000 / wMs;
              final remaining = size - sent;
              info.etaSeconds =
                  info.speedBps > 0 ? remaining ~/ info.speedBps : null;
              windowStart = now;
              windowBytes = 0;
            }
            if (now.difference(lastUi).inMilliseconds > 250) {
              lastUi = now;
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
      info.speedBps = 0;
      info.etaSeconds = 0;
      onUpdate(info);
    } catch (e) {
      info.status = TransferStatus.failed;
      info.error = e.toString().replaceFirst('Exception: ', '');
      onUpdate(info);
    }
  }

  /// Sends a text snippet. The text travels inside the offer; the receiver
  /// saves it as a .txt file on accept. No upload step.
  Future<void> sendText({
    required PeerDevice peer,
    required String text,
    required String senderName,
    String? senderId,
    required void Function(TransferInfo info) onUpdate,
    Duration acceptTimeout = const Duration(seconds: 90),
  }) async {
    final now = DateTime.now();
    final filename =
        'beamo-note-${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.txt';
    final info = TransferInfo(
      id: const Uuid().v4(),
      filename: filename,
      size: text.length,
      peerName: peer.name,
      direction: TransferDirection.sending,
      kind: TransferKind.text,
    );
    onUpdate(info);

    final offerId = await _postOffer(
      peer: peer,
      info: info,
      onUpdate: onUpdate,
      body: {
        'filename': filename,
        'size': text.length,
        'senderName': senderName,
        if (senderId != null) 'senderId': senderId,
        'kind': 'text',
        'text': text,
      },
    );
    if (offerId == null) return;

    info.status = TransferStatus.waitingAccept;
    onUpdate(info);
    final accepted = await _waitForAccept(peer, offerId, acceptTimeout);
    info.status = accepted ? TransferStatus.done : TransferStatus.declined;
    if (accepted) info.progress = 1.0;
    onUpdate(info);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Posts the offer; returns the offer id, or null (with [info] failed)
  /// when the receiver could not be reached.
  Future<String?> _postOffer({
    required PeerDevice peer,
    required TransferInfo info,
    required void Function(TransferInfo info) onUpdate,
    required Map<String, dynamic> body,
  }) async {
    http.Response offerRes;
    try {
      offerRes = await _client
          .post(
            Uri.parse('${_base(peer)}/offer'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      info.status = TransferStatus.failed;
      info.error = 'No response from ${peer.name}';
      onUpdate(info);
      return null;
    }
    if (offerRes.statusCode != 200) {
      info.status = TransferStatus.failed;
      info.error = 'Offer rejected (HTTP ${offerRes.statusCode})';
      onUpdate(info);
      return null;
    }
    return (jsonDecode(offerRes.body) as Map<String, dynamic>)['id'] as String;
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
          // Text offers complete server-side without an upload step.
          if (status == 'done') return true;
        }
      } catch (_) {
        // transient — keep polling
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}
