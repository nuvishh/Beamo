/// A device discovered on the local network (or added manually).
class PeerDevice {
  final String name;
  final String host;
  final int port;

  const PeerDevice({
    required this.name,
    required this.host,
    required this.port,
  });

  String get address => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is PeerDevice &&
      other.name == name &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(name, host, port);

  @override
  String toString() => 'PeerDevice($name @ $address)';
}
