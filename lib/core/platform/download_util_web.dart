// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Descarga un archivo en web creando un anchor temporal con `download` attr.
/// Si el browser ignora el attribute (CORS / cross-origin sin
/// Content-Disposition), abre el recurso en una pestaña nueva como fallback.
Future<void> downloadFile(String url, String filename) async {
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..target = '_blank'
      ..rel = 'noopener';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } catch (_) {
    html.window.open(url, '_blank');
  }
}

bool get canDownload => true;
