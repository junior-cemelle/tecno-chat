// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Solicita micrófono (y cámara si [video] es true) vía getUserMedia.
///
/// En web hay que disparar el diálogo de permisos del navegador ANTES de
/// inicializar Agora — si solo se llama a `engine.enableVideo()`, el plugin
/// puede no disparar el prompt correctamente y la pista de video queda muda.
/// Liberamos las pistas inmediatamente: Agora creará sus propias instancias
/// con los permisos ya concedidos.
Future<bool> requestMediaPermissions({required bool video}) async {
  try {
    final stream = await html.window.navigator.mediaDevices?.getUserMedia({
      'audio': true,
      if (video) 'video': true,
    });
    stream?.getTracks().forEach((t) => t.stop());
    return stream != null;
  } catch (_) {
    return false;
  }
}
