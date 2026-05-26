import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia y validación del JWT del SII.
///
/// El token se guarda en SharedPreferences (localStorage en web, NSUserDefaults
/// en iOS, SharedPreferences en Android). No es almacenamiento "secure" pero
/// el JWT del SII es de corta vida y no concede más privilegios que Firebase
/// Auth (que también persiste su refresh token en almacenamiento cliente).
///
/// Para algo más sensible (passwords, etc.) usar `flutter_secure_storage` —
/// no aplica aquí porque el JWT ya expira solo y se descarta automáticamente
/// vía [isTokenExpired].
class SiiTokenStorage {
  static const _kTokenKey = 'sii_token';

  final SharedPreferences _prefs;
  const SiiTokenStorage(this._prefs);

  /// Inyectable como singleton — crear una sola vez al iniciar la app:
  /// ```dart
  /// final storage = await SiiTokenStorage.create();
  /// ```
  static Future<SiiTokenStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SiiTokenStorage(prefs);
  }

  /// Lee el token persistido. Si está expirado, lo elimina y devuelve null
  /// para que el caller no haga requests con un JWT muerto.
  String? readToken() {
    final token = _prefs.getString(_kTokenKey);
    if (token == null || token.isEmpty) return null;
    if (isTokenExpired(token)) {
      _prefs.remove(_kTokenKey);
      return null;
    }
    return token;
  }

  Future<void> saveToken(String token) async {
    await _prefs.setString(_kTokenKey, token);
  }

  Future<void> clearToken() async {
    await _prefs.remove(_kTokenKey);
  }

  // ─── JWT helpers ───────────────────────────────────────────────────────────

  /// Decodifica el payload del JWT y revisa el claim `exp` (segundos UNIX).
  ///
  ///  - true  → token expirado o malformado (treat-as-expired por seguridad)
  ///  - false → exp en el futuro (o no tiene exp, asumimos válido)
  ///
  /// NO valida la firma — eso lo hace el backend. Solo evita mandar tokens
  /// obviamente muertos y da feedback inmediato al cargar la app.
  static bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return true;

      final payload = _base64UrlDecode(parts[1]);
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final exp = json['exp'];
      if (exp is! num) return false; // sin claim exp → asumir válido
      final expiryMs = exp.toInt() * 1000;
      return expiryMs < DateTime.now().millisecondsSinceEpoch;
    } catch (_) {
      return true; // malformado → tratar como expirado
    }
  }

  /// Devuelve los claims del JWT como Map, o null si el token es inválido.
  /// Útil para extraer información embebida (sub, email, roles, etc.).
  static Map<String, dynamic>? decodeClaims(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = _base64UrlDecode(parts[1]);
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Decodifica base64url con padding (los JWT no traen padding pero
  /// `base64Url.decode` lo requiere).
  static String _base64UrlDecode(String input) {
    var normalized = input;
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
        break;
      case 3:
        normalized += '=';
        break;
    }
    return utf8.decode(base64Url.decode(normalized));
  }
}
