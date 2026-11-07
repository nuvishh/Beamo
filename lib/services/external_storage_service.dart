import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// USB / external-storage save folder, picked once via the system folder
/// picker (SAF) and remembered.
///
/// Works on phones and TV sideloads alike: the picker is a system UI
/// (D-pad navigable on TV), and later saves need no UI at all — received
/// files go straight to the picked folder. If the drive is removed or the
/// permission is revoked, the saved folder is forgotten and saves fall
/// back to Downloads until the user picks again.
class UsbFolder {
  final String uri;
  final String name;
  const UsbFolder({required this.uri, required this.name});
}

class ExternalStorageService {
  static const _uriKey = 'beamo_usb_folder_uri_v1';
  static const _nameKey = 'beamo_usb_folder_name_v1';
  static const _channel = MethodChannel('beamo/usb');

  static bool get supported => Platform.isAndroid;

  static Future<UsbFolder?> savedFolder() async {
    if (!supported) return null;
    final p = await SharedPreferences.getInstance();
    final uri = p.getString(_uriKey);
    final name = p.getString(_nameKey);
    if (uri == null || uri.isEmpty) return null;
    return UsbFolder(uri: uri, name: name ?? 'USB folder');
  }

  /// Opens the system folder picker. Returns the picked folder, or null
  /// when the user cancelled.
  static Future<UsbFolder?> pickFolder() async {
    if (!supported) return null;
    Map<String, dynamic>? res;
    try {
      res = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') return null;
      rethrow;
    }
    if (res == null) return null;
    final uri = res['uri']?.toString() ?? '';
    final name = res['name']?.toString() ?? 'USB folder';
    if (uri.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    await p.setString(_uriKey, uri);
    await p.setString(_nameKey, name);
    return UsbFolder(uri: uri, name: name);
  }

  static Future<void> clearFolder() async {
    final folder = await savedFolder();
    final p = await SharedPreferences.getInstance();
    await p.remove(_uriKey);
    await p.remove(_nameKey);
    if (folder != null && supported) {
      try {
        await _channel.invokeMethod('releaseFolder', {'treeUri': folder.uri});
      } catch (_) {}
    }
  }

  /// Streams a staged file into the saved USB folder.
  /// Returns a display string on success, null on failure.
  /// A lost permission clears the saved folder so the next save falls back.
  static Future<String?> saveToUsb(String sourcePath, String filename) async {
    final folder = await savedFolder();
    if (folder == null) return null;
    try {
      final display = await _channel.invokeMethod<String>('writeFile', {
        'treeUri': folder.uri,
        'sourcePath': sourcePath,
        'filename': filename,
      });
      if (display == null || display.isEmpty) return null;
      try {
        await File(sourcePath).delete();
      } catch (_) {}
      return display;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_LOST') {
        final p = await SharedPreferences.getInstance();
        await p.remove(_uriKey);
        await p.remove(_nameKey);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
