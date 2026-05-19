import 'dart:io';
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
  };

  /// Sube la imagen de un story (sobreescribe si ya existe).
  Future<String> uploadStoryImage(String storyId, File file) async {
    final path = 'stories/$storyId.jpg';
    await _storage.from(_bucket).upload(
          path,
          file,
          fileOptions: const FileOptions(
              contentType: 'image/jpeg', upsert: true),
        );
    final base = _storage.from(_bucket).getPublicUrl(path);
    return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Sube el avatar de un grupo (sobreescribe si ya existe).
  Future<String> uploadGroupAvatar(String chatId, File file) async {
    final path = '$chatId/group-avatar.jpg';
    await _storage.from(_bucket).upload(
          path,
          file,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true, // sobreescribir en actualizaciones
          ),
        );
    // Añadir timestamp para invalidar caché del CDN
    final base = _storage.from(_bucket).getPublicUrl(path);
    return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Sube un archivo al bucket y devuelve la URL pública.
  Future<String> uploadChatMedia({
    required String chatId,
    required File file,
    required String folder, // 'images' | 'videos' | 'audio'
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '$chatId/$folder/$name';

    await _storage.from(_bucket).upload(
          path,
          file,
          fileOptions: FileOptions(
            contentType: _mime[ext] ?? 'application/octet-stream',
            upsert: false,
          ),
        );

    return _storage.from(_bucket).getPublicUrl(path);
  }
}
