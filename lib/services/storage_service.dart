import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'external_storage_service.dart';

/// Staging dir for incoming uploads (app-private; no permission needed).
///
/// Android: app-specific external dir. TV sideloads work fine with this.
/// iOS: app documents directory.
Future<Directory> defaultSaveDir() async {
  final Directory base;
  if (Platform.isAndroid) {
    base = (await getExternalStorageDirectory()) ??
        await getApplicationDocumentsDirectory();
  } else {
    base = await getApplicationDocumentsDirectory();
  }
  final target = Directory('${base.path}/Beamo');
  if (!await target.exists()) {
    await target.create(recursive: true);
  }
  return target;
}

/// Saves a staged received file to its final home: the user-picked USB
/// folder when one is set, else the public Downloads/Beamo folder.
/// Returns the display path, or null when both failed — the caller then
/// keeps the staged file as-is.
Future<String?> saveReceivedFile(String sourcePath, String filename) async {
  if (Platform.isAndroid) {
    final usbPath =
        await ExternalStorageService.saveToUsb(sourcePath, filename);
    if (usbPath != null) return usbPath;
  }
  return saveToPublicDownloads(sourcePath, filename);
}

/// Moves a staged file into the public Downloads/Beamo folder on Android
/// (via MediaStore on API 29+, direct copy below that).
///
/// Returns the public path, or null when the move failed — the caller then
/// keeps the staged file as-is.
Future<String?> saveToPublicDownloads(
    String sourcePath, String filename) async {
  if (!Platform.isAndroid) return null;
  try {
    const channel = MethodChannel('beamo/downloads');
    final path = await channel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': sourcePath,
      'filename': filename,
    });
    if (path == null || path.isEmpty) return null;
    // Remove the staged copy; the public one is now canonical.
    try {
      await File(sourcePath).delete();
    } catch (_) {}
    return path;
  } catch (_) {
    return null;
  }
}
