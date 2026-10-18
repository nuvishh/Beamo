import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Trusted-device store for auto-accept.
///
/// Each device gets a stable random ID (stored locally). Senders include it
/// in the offer; receivers auto-accept offers from IDs the user trusted.
class TrustedService {
  static const _trustedKey = 'beamo_trusted_ids_v1';
  static const _deviceIdKey = 'beamo_device_id_v1';

  /// Stable per-device ID, generated once and reused forever.
  static Future<String> deviceId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await p.setString(_deviceIdKey, id);
    }
    return id;
  }

  static Future<Set<String>> trustedIds() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_trustedKey) ?? const []).toSet();
  }

  static Future<bool> isTrusted(String? id) async {
    if (id == null || id.isEmpty) return false;
    return (await trustedIds()).contains(id);
  }

  static Future<void> addTrusted(String id) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_trustedKey) ?? const []).toSet()..add(id);
    await p.setStringList(_trustedKey, set.toList());
  }

  static Future<void> removeTrusted(String id) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_trustedKey) ?? const []).toSet()
      ..remove(id);
    await p.setStringList(_trustedKey, set.toList());
  }
}
