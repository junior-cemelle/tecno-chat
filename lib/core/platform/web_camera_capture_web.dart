// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// Abre una superposición HTML que muestra el stream de la webcam del usuario
/// (via getUserMedia), permite capturar un fotograma y lo devuelve como [XFile].
///
/// Retorna null si el usuario cancela, deniega el permiso o no hay cámara.
/// La superposición es puro HTML/CSS — no usa HtmlElementView — por lo que
/// funciona con ambos renderers (CanvasKit y HTML) sin conflictos de z-index.
Future<XFile?> captureFromWebCamera() async {
  // ── 1. Solicitar acceso a la cámara ──────────────────────────────────────
  html.MediaStream? stream;
  try {
    stream = await html.window.navigator.mediaDevices?.getUserMedia({
      'video': {
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'facingMode': 'environment',
      },
      'audio': false,
    });
  } catch (_) {
    return null; // Permiso denegado o sin cámara disponible
  }
  if (stream == null) return null;

  final completer = Completer<XFile?>();

  // ── 2. Crear superposición HTML ───────────────────────────────────────────
  final overlay = html.DivElement()
    ..style.cssText = '''
      position: fixed; inset: 0;
      background: rgba(0,0,0,0.92);
      z-index: 99998;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      font-family: 'Poppins', sans-serif;
    ''';

  // Título
  final title = html.HeadingElement.h3()
    ..text = 'Cámara'
    ..style.cssText = 'color:white; margin:0 0 16px; font-size:18px;';

  // Elemento de video
  final video = html.VideoElement()
    ..srcObject = stream
    ..autoplay = true
    ..muted = true
    ..style.cssText = '''
      max-width: 80vw; max-height: 60vh;
      border-radius: 12px; object-fit: cover;
      background: #111;
    ''';

  // Fila de botones
  final btnRow = html.DivElement()
    ..style.cssText = 'display:flex; gap:16px; margin-top:24px;';

  const btnBase = '''
    padding: 12px 32px; font-size: 15px; font-weight: 600;
    border-radius: 10px; border: none; cursor: pointer; outline: none;
  ''';

  final captureBtn = html.ButtonElement()
    ..text = '📷  Capturar'
    ..style.cssText = '${btnBase}background:#834F8A; color:white;';

  final cancelBtn = html.ButtonElement()
    ..text = 'Cancelar'
    ..style.cssText =
        '${btnBase}background:transparent; color:white; border: 1px solid rgba(255,255,255,0.4);';

  // ── 3. Función de limpieza ────────────────────────────────────────────────
  void cleanup() {
    stream?.getTracks().forEach((t) => t.stop());
    overlay.remove();
  }

  // ── 4. Captura: dibuja el frame en canvas y extrae JPEG ───────────────────
  captureBtn.onClick.listen((_) async {
    final w = video.videoWidth;
    final h = video.videoHeight;
    if (w == 0 || h == 0) return;

    final canvas = html.CanvasElement(width: w, height: h);
    canvas.context2D.drawImage(video, 0, 0);

    // toDataUrl es síncrono en canvas 2D; devuelve data:image/jpeg;base64,...
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
    final base64 = dataUrl.split(',').last;
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64);
    } catch (_) {
      cleanup();
      completer.complete(null);
      return;
    }

    cleanup();
    completer.complete(XFile.fromData(
      bytes,
      name: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: 'image/jpeg',
    ));
  });

  // ── 5. Cancelar ───────────────────────────────────────────────────────────
  cancelBtn.onClick.listen((_) {
    cleanup();
    completer.complete(null);
  });

  // Click fuera del video también cancela
  overlay.onClick.listen((e) {
    if (e.target == overlay) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    }
  });

  btnRow.children.addAll([captureBtn, cancelBtn]);
  overlay.children.addAll([title, video, btnRow]);
  html.document.body?.append(overlay);

  return completer.future;
}
