import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
