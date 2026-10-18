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
  final String? senderId;
  final TransferKind kind;
  final String? text;

  IncomingOffer({
    required this.id,
    required this.filename,
    required this.size,
    required this.senderName,
    this.senderId,
    this.kind = TransferKind.file,
    this.text,
  });

  bool get isText => kind == TransferKind.text;
}

class _OfferState {
  final IncomingOffer offer;
  String status = 'pending';
  _OfferState({required this.offer});
}

/// HTTP server run by the RECEIVER.
///
/// Protocol:
///   GET  /                      -> browser upload page (HTML)
///   GET  /ping                  -> {"name": ..., "version": 2}
///   POST /offer                 -> {"ok": true, "id": ...}
///          body: filename, size, senderName, [senderId, kind, text]
///   GET  /offer/<id>/status     -> {"status": "pending|accepted|declined|..."}
///   POST /upload/<id>           -> raw bytes, returns {"ok": true}
class ShareServer {
  static const int defaultPort = 8080;
  static const int protocolVersion = 2;

  final String deviceName;
  final Future<bool> Function(IncomingOffer offer) onOffer;
  final void Function(TransferInfo info) onTransferUpdate;

  /// Returns true when [senderId] belongs to a trusted device
  /// (auto-accept, no dialog).
  final bool Function(String? senderId) isTrusted;

  HttpServer? _server;
  final Map<String, _OfferState> _offers = {};
  DateTime _lastUiPush = DateTime.fromMillisecondsSinceEpoch(0);

  ShareServer({
    required this.deviceName,
    required this.onOffer,
    required this.onTransferUpdate,
    bool Function(String? senderId)? isTrusted,
  }) : isTrusted = isTrusted ?? ((_) => false);

  bool get running => _server != null;
  int get port => _server?.port ?? defaultPort;

  Future<void> start({int port = defaultPort}) async {
    await stop();
    final router = Router()
      ..get('/', _handleBrowserPage)
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
        jsonEncode({'name': deviceName, 'version': protocolVersion}),
        headers: {'content-type': 'application/json'},
      );

  Response _handleBrowserPage(Request req) => Response.ok(
        _browserPageHtml(),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  Future<Response> _handleOffer(Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final kind = (data['kind']?.toString() == 'text')
          ? TransferKind.text
          : TransferKind.file;
      final filename = _sanitizeFilename((data['filename'] ?? 'file').toString());
      final size = (data['size'] as num?)?.toInt() ?? 0;
      final sender = (data['senderName'] ?? 'Unknown device').toString();
      final senderId = data['senderId']?.toString();
      final text = kind == TransferKind.text
          ? data['text']?.toString() ?? ''
          : null;

      final id = const Uuid().v4();
      final offer = IncomingOffer(
        id: id,
        filename: filename,
        size: size,
        senderName: sender,
        senderId: senderId,
        kind: kind,
        text: text,
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
    bool accepted;
    if (isTrusted(offer.senderId)) {
      accepted = true; // trusted device: skip the dialog entirely
    } else {
      try {
        accepted = await onOffer(offer);
      } catch (_) {
        accepted = false;
      }
    }
    final state = _offers[id];
    if (state != null && state.status == 'pending') {
      state.status = accepted ? 'accepted' : 'declined';
      if (accepted && offer.isText) {
        // Text offers carry their payload in the offer itself — no upload.
        await _completeTextOffer(id, offer);
      } else {
        // Expire declined/accepted-but-never-uploaded offers after 3 min.
        Timer(const Duration(minutes: 3), () => _offers.remove(id));
      }
    }
  }

  /// Writes an accepted text offer to a .txt file in Downloads.
  Future<void> _completeTextOffer(String id, IncomingOffer offer) async {
    final info = TransferInfo(
      id: id,
      filename: offer.filename,
      size: offer.text?.length ?? 0,
      peerName: offer.senderName,
      direction: TransferDirection.receiving,
      kind: TransferKind.text,
      status: TransferStatus.inProgress,
    );
    onTransferUpdate(info);
    try {
      final dir = await defaultSaveDir();
      final target =
          await _uniqueFile(File('${dir.path}/${offer.filename}'));
      await target.writeAsString(offer.text ?? '');
      final publicPath =
          await saveToPublicDownloads(target.path, offer.filename);
      info.savedPath = publicPath ?? target.path;
      info.status = TransferStatus.done;
      info.progress = 1.0;
    } catch (e) {
      info.status = TransferStatus.failed;
      info.error = e.toString();
    }
    _offers[id]?.status = info.status == TransferStatus.done ? 'done' : 'failed';
    onTransferUpdate(info);
    _offers.remove(id);
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

      // Speed tracking: 1-second windows.
      var windowStart = DateTime.now();
      var windowBytes = 0;

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
        windowBytes += chunk.length;
        info.progress = total > 0 ? received / total : 0;

        final now = DateTime.now();
        final wMs = now.difference(windowStart).inMilliseconds;
        if (wMs >= 1000) {
          info.speedBps = windowBytes * 1000 / wMs;
          final remaining = total - received;
          info.etaSeconds =
              info.speedBps > 0 ? remaining ~/ info.speedBps : null;
          windowStart = now;
          windowBytes = 0;
        }
        pushUi();
      }
      await sink.flush();
      await sink.close();

      // Move into the public Downloads/Beamo folder (Android).
      final publicPath =
          await saveToPublicDownloads(target.path, state.offer.filename);

      state.status = 'done';
      info.status = TransferStatus.done;
      info.progress = 1.0;
      info.speedBps = 0;
      info.etaSeconds = 0;
      info.savedPath = publicPath ?? target.path;
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

  String _browserPageHtml() {
    final name = const HtmlEscape().convert(deviceName);
    return '''<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beamo — send to $name</title>
<style>
body{font-family:system-ui,sans-serif;background:#0e1116;color:#e6edf3;
display:flex;justify-content:center;padding:32px 16px;margin:0}
.card{background:#161b22;border:1px solid #2a3342;border-radius:16px;
padding:28px;max-width:440px;width:100%;text-align:center}
h2{margin:0 0 6px;font-size:20px} p{color:#8b98a9;font-size:13px}
input[type=file]{margin:18px 0;width:100%;color:#8b98a9}
button{background:#2f81f7;color:#fff;border:0;border-radius:10px;
padding:12px 28px;font-size:15px;font-weight:700;cursor:pointer;width:100%}
button:disabled{opacity:.5} #s{margin-top:14px;font-size:13px;min-height:20px}
.bar{height:6px;background:#2a3342;border-radius:3px;margin-top:10px;overflow:hidden}
.bar>div{height:100%;background:#2f81f7;width:0%}
</style></head><body><div class="card">
<h2>⚡ Beamo</h2><p>Send a file to <b>$name</b> from this browser.<br>
No app needed — same Wi-Fi only.</p>
<input type="file" id="f"><button id="b">Send file</button>
<div class="bar"><div id="p"></div></div><div id="s"></div>
<script>
const f=document.getElementById('f'),b=document.getElementById('b'),
s=document.getElementById('s'),p=document.getElementById('p');
b.onclick=async()=>{
 const file=f.files[0]; if(!file){s.textContent='Pick a file first.';return;}
 b.disabled=true; s.textContent='Offering…';
 try{
  const o=await(await fetch('/offer',{method:'POST',
   headers:{'content-type':'application/json'},
   body:JSON.stringify({filename:file.name,size:file.size,senderName:'Browser'})})).json();
  const id=o.id;
  while(true){
   const st=await(await fetch('/offer/'+id+'/status')).json();
   if(st.status==='accepted'||st.status==='uploading')break;
   if(st.status==='declined'){s.textContent='Declined on receiver.';b.disabled=false;return;}
   if(st.status==='failed'){s.textContent='Offer failed.';b.disabled=false;return;}
   await new Promise(r=>setTimeout(r,1000));
  }
  s.textContent='Uploading — accept on the receiver if asked…';
  const up=await fetch('/upload/'+id,{method:'POST',body:file,
   duplex:'half',headers:{'content-type':'application/octet-stream'}});
  if(up.ok){s.textContent='Done ✓ — check Downloads/Beamo on the receiver.';p.style.width='100%';}
  else{s.textContent='Upload failed: '+await up.text();}
 }catch(e){s.textContent='Error: '+e.message;}
 b.disabled=false;
};
</script></div></body></html>''';
  }
}
