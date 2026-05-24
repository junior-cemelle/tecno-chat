import 'dart:io';

Future<void> deleteFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}
