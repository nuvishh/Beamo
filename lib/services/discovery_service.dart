import 'dart:async';

import 'package:nsd/nsd.dart';

import '../models/peer_device.dart';

/// mDNS (Bonjour/NSD) advertising + browsing for Beamo peers.
///
/// Receiver advertises `_beamo._tcp`; sender browses for it.
/// If mDNS fails (some hotspots block multicast), the UI offers
/// manual IP entry as a fallback — the HTTP protocol doesn't care
/// how the peer address was learned.
class DiscoveryService {
  static const String serviceType = '_beamo._tcp';

  dynamic _registration; // NsdRegistration
  Discovery? _discovery;

  final _peers = <String, PeerDevice>{};
  final _peersController = StreamController<List<PeerDevice>>.broadcast();

  /// Emits the current peer list whenever it changes.
  Stream<List<PeerDevice>> get peers => _peersController.stream;

  List<PeerDevice> get currentPeers => _peers.values.toList();

  // ---------- advertising (receiver side) ----------

  Future<void> startAdvertising(String deviceName, int port) async {
    await stopAdvertising();
    try {
      _registration = await register(
        Service(name: deviceName, type: serviceType, port: port),
      );
    } catch (_) {
      // Advertising unsupported/failed — manual IP entry still works.
      _registration = null;
    }
  }

  Future<void> stopAdvertising() async {
    final reg = _registration;
    _registration = null;
    if (reg != null) {
      try {
        await unregister(reg);
      } catch (_) {}
    }
  }

  // ---------- browsing (sender side) ----------

  Future<void> startBrowsing() async {
    await stopBrowsing();
    try {
      _discovery = await startDiscovery(serviceType);
      _discovery!.addListener(_refreshPeers);
      _refreshPeers();
    } catch (_) {
      _discovery = null;
    }
  }

  void _refreshPeers() {
    final d = _discovery;
    if (d == null) return;
    _peers.clear();
    for (final s in d.services) {
      final host = s.host;
      final name = s.name;
      final port = s.port;
      if (host == null || host.isEmpty || name == null || port == null) {
        continue;
      }
      final key = '$name@$host:$port';
      _peers[key] = PeerDevice(name: name, host: host, port: port);
    }
    if (!_peersController.isClosed) {
      _peersController.add(currentPeers);
    }
  }

  Future<void> stopBrowsing() async {
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      try {
        await stopDiscovery(d);
      } catch (_) {}
    }
    _peers.clear();
    if (!_peersController.isClosed) _peersController.add(const []);
  }

  void dispose() {
    _peersController.close();
  }
}
