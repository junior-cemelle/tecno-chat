import 'package:permission_handler/permission_handler.dart';

/// Solicita los permisos de medios (micrófono — y cámara si [video] es true).
///
/// En Android 6+ y iOS hay que pedir CAMERA/MICROPHONE en runtime aunque
/// estén declarados en AndroidManifest/Info.plist. Agora **no** dispara
/// estos prompts por sí mismo: si no se piden antes de `enableVideo()`, la
/// cámara queda muda (la pista de video se publica vacía) y el otro extremo
/// no ve nada — el audio sigue funcionando porque Record sí pide el mic.
Future<bool> requestMediaPermissions({required bool video}) async {
  final perms = <Permission>[Permission.microphone];
  if (video) perms.add(Permission.camera);

  final results = await perms.request();
  return results.values.every((s) => s.isGranted || s.isLimited);
}
