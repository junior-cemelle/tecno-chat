import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  static final _storage = Supabase.instance.client.storage;
  static const _bucket = 'chat-media';

  static const _mime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4a': 'audio/m4a',
    'aac': 'audio/aac',
    'mp3': 'audio/mpeg',
    'webm': 'audio/webm',
    'ogg': 'audio/ogg',
  };

  /// Sube la imagen de un story. Usa bytes para compatibilidad web/móvil.
  Future<String> uploadStoryImage(String storyId, XFile xfile) async {
    final path = 'stories/$storyId.jpg';
    final bytes = await xfile.readAsBytes();
    await _storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
              contentType: 'image/jpeg', upsert: true),
        );
    final base = _storage.from(_bucket).getPublicUrl(path);
    return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Sube el avatar de un usuario a Supabase.
  Future<String> uploadUserAvatar(String uid, XFile xfile) async {
    final path = 'avatars/$uid.jpg';
    final bytes = await xfile.readAsBytes();
    await _storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final base = _storage.from(_bucket).getPublicUrl(path);
    return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Sube el avatar de un grupo.
  Future<String> uploadGroupAvatar(String chatId, XFile xfile) async {
    final path = '$chatId/group-avatar.jpg';
    final bytes = await xfile.readAsBytes();
    await _storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final base = _storage.from(_bucket).getPublicUrl(path);
    return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Sube cualquier archivo de media y devuelve su URL pública.
  ///
  /// La extensión se determina a partir de [XFile.name] (más confiable que
  /// [XFile.path], ya que en web `path` puede ser un blob URL sin extensión —
  /// p.ej. `blob:http://localhost:5005/uuid`). Para audios grabados en web
  /// usa `XFile(blobUrl, name: 'audio.webm')` para que la extensión llegue
  /// aquí correctamente.
  Future<String> uploadChatMedia({
    required String chatId,
    required XFile xfile,
    required String folder, // 'images' | 'videos' | 'audio' | 'thumbnails'
  }) async {
    final fname = xfile.name;
    final ext = fname.contains('.')
        ? fname.split('.').last.toLowerCase()
        : 'bin';
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '$chatId/$folder/$name';
    final bytes = await xfile.readAsBytes();

    await _storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _mime[ext] ?? 'application/octet-stream',
          ),
        );

    return _storage.from(_bucket).getPublicUrl(path);
  }
}
