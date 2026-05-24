/// Mobile: por ahora no descarga (los usuarios pueden mantener presionado
/// la imagen / video para guardarla con el menú nativo del sistema).
Future<void> downloadFile(String url, String filename) async {}

/// Indica si la plataforma actual soporta descarga programática.
bool get canDownload => false;
