import 'dart:typed_data';

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

  /// Sube el avatar de un usuario a Supabase desde un XFile.
  Future<String> uploadUserAvatar(String uid, XFile xfile) async {
    final bytes = await xfile.readAsBytes();
    return uploadUserAvatarBytes(uid, bytes);
  }

  /// Sube el avatar de un usuario a Supabase desde bytes ya cargados.
  /// Útil para fuentes que no pasan por XFile (p.ej. decodificación de
  /// base64 del SII), evitando el round-trip XFile.fromData → readAsBytes
  /// que en web puede fallar silenciosamente.
  Future<String> uploadUserAvatarBytes(String uid, Uint8List bytes) async {
    final path = 'avatars/$uid.jpg';
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

  /// Sube el CV en PDF de una solicitud de asesoría. Devuelve la URL pública.
  ///
  /// El [tempKey] permite subir el PDF ANTES de que exista el doc en Firestore
  /// (típicamente el uid del asesor + un timestamp). Una vez creado el doc,
  /// la URL queda guardada en `Asesoria.cvUrl` — no movemos el archivo, la
  /// ruta original sigue válida.
  Future<String> uploadAsesoriaCv(String tempKey, Uint8List bytes) async {
    final path = 'asesorias/cvs/$tempKey.pdf';
    await _storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
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
