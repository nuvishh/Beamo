import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Local-network helpers.
class NetworkService {
  /// Returns the device's Wi-Fi IPv4 address, e.g. "192.168.1.5".
  /// Null when not on Wi-Fi (or permission missing on Android).
  static Future<String?> getLocalIp() async {
    try {
      return await NetworkInfo().getWifiIP();
    } catch (_) {
      return null;
    }
  }

  /// Best-effort device name for mDNS advertising.
  static String defaultDeviceName() {
    if (Platform.isAndroid) return 'Android TV';
    if (Platform.isIOS) return 'iPhone';
    return 'Beamo Device';
  }
}
