import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where received files are saved.
///
/// Android: app-specific external dir (no storage permission needed,
/// visible in file managers). TV sideloads work fine with this.
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
