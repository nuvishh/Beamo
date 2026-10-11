import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../models/transfer.dart';
import 'storage_service.dart';

/// An offer announced by a sender, awaiting the user's accept/decline.
class IncomingOffer {
  final String id;
  final String filename;
  final int size;
  final String senderName;

  IncomingOffer({
    required this.id,
    required this.filename,
    required this.size,
    required this.senderName,
  });
}

class _OfferState {
  final IncomingOffer offer;
  String status = 'pending';
  _OfferState({required this.offer});
}

/// HTTP server run by the RECEIVER.
///
/// Protocol:
///   GET  /ping                 -> {"name": ..., "version": 1}
///   POST /offer                -> {"ok": true, "id": ...}   (body: filename, size, senderName)
///   GET  /offer/<id>/status    -> {"status": "pending|accepted|declined|..."}
///   POST /upload/<id>          -> raw bytes, returns {"ok": true}
class ShareServer {
  static const int defaultPort = 8080;

  final String deviceName;
  final Future<bool> Function(IncomingOffer offer) onOffer;
  final void Function(TransferInfo info) onTransferUpdate;

  HttpServer? _server;
  final Map<String, _OfferState> _offers = {};
  DateTime _lastUiPush = DateTime.fromMillisecondsSinceEpoch(0);

  ShareServer({
    required this.deviceName,
    required this.onOffer,
    required this.onTransferUpdate,
  });

  bool get running => _server != null;
  int get port => _server?.port ?? defaultPort;

  Future<void> start({int port = defaultPort}) async {
    await stop();
    final router = Router()
      ..get('/ping', _handlePing)
      ..post('/offer', _handleOffer)
      ..get('/offer/<id>/status', _handleOfferStatus)
      ..post('/upload/<id>', _handleUpload);

    _server = await shelf_io.serve(
      router.call,
      InternetAddress.anyIPv4,
      port,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _offers.clear();
  }

  // ---------- handlers ----------

  Response _handlePing(Request req) => Response.ok(
        jsonEncode({'name': deviceName, 'version': 1}),
        headers: {'content-type': 'application/json'},
      );

  Future<Response> _handleOffer(Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final filename = _sanitizeFilename((data['filename'] ?? 'file').toString());
      final size = (data['size'] as num?)?.toInt() ?? 0;
      final sender = (data['senderName'] ?? 'Unknown device').toString();

      final id = const Uuid().v4();
      final offer = IncomingOffer(
        id: id,
        filename: filename,
        size: size,
        senderName: sender,
      );
      _offers[id] = _OfferState(offer: offer);

      // Ask the UI without blocking this response — the sender polls
      // /offer/<id>/status until the user decides.
      unawaited(_askUser(id, offer));

      return Response.ok(
        jsonEncode({'ok': true, 'id': id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(400, body: 'bad offer: $e');
    }
  }

  Future<void> _askUser(String id, IncomingOffer offer) async {
    bool accepted = false;
    try {
      accepted = await onOffer(offer);
    } catch (_) {
      accepted = false;
    }
    final state = _offers[id];
    if (state != null && state.status == 'pending') {
      state.status = accepted ? 'accepted' : 'declined';
      // Expire declined/accepted-but-never-uploaded offers after 3 min.
      Timer(const Duration(minutes: 3), () => _offers.remove(id));
    }
  }

  Response _handleOfferStatus(Request req, String id) {
    final state = _offers[id];
    if (state == null) return Response.notFound('unknown offer');
    return Response.ok(
      jsonEncode({'status': state.status}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleUpload(Request req, String id) async {
    final state = _offers[id];
    if (state == null) return Response.notFound('unknown offer');
    if (state.status != 'accepted') {
      return Response.forbidden('offer not accepted');
    }
    state.status = 'uploading';

    final info = TransferInfo(
      id: id,
      filename: state.offer.filename,
      size: state.offer.size,
      peerName: state.offer.senderName,
      direction: TransferDirection.receiving,
      status: TransferStatus.inProgress,
    );

    try {
      final dir = await defaultSaveDir();
      final target = await _uniqueFile(File('${dir.path}/${state.offer.filename}'));
      final sink = target.openWrite();
      var received = 0;
      final total = state.offer.size;

      void pushUi({bool force = false}) {
        final now = DateTime.now();
        if (force || now.difference(_lastUiPush).inMilliseconds > 250) {
          _lastUiPush = now;
          onTransferUpdate(info);
        }
      }

      pushUi(force: true);
      await for (final chunk in req.read()) {
        sink.add(chunk);
        received += chunk.length;
        info.progress = total > 0 ? received / total : 0;
        pushUi();
      }
      await sink.flush();
      await sink.close();

      state.status = 'done';
      info.status = TransferStatus.done;
      info.progress = 1.0;
      info.savedPath = target.path;
      pushUi(force: true);
      _offers.remove(id);

      return Response.ok(
        jsonEncode({'ok': true}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      state.status = 'failed';
      info.status = TransferStatus.failed;
      info.error = e.toString();
      onTransferUpdate(info);
      return Response.internalServerError(body: 'upload failed: $e');
    }
  }

  // ---------- helpers ----------

  static String _sanitizeFilename(String name) {
    final clean = name.replaceAll(RegExp(r'[^\w.\- ]'), '_').trim();
    if (clean.isEmpty || clean == '.' || clean == '..') return 'file';
    return clean;
  }

  /// Avoids overwriting: photo.jpg -> photo (1).jpg
  static Future<File> _uniqueFile(File file) async {
    if (!await file.exists()) return file;
    final dir = file.parent.path;
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (true) {
      final candidate = File('$dir/$base ($i)$ext');
      if (!await candidate.exists()) return candidate;
      i++;
    }
  }
}
