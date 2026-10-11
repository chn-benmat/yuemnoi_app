import 'dart:io';

Future<void> clearCameraFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
