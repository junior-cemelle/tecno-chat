import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/sii_models.dart';

/// Excepción para errores del backend SII. Incluye el código HTTP cuando
/// está disponible para que la UI pueda diferenciar 401/403 (sesión expirada)
/// de otros errores.
class SiiApiException implements Exception {
  final int? statusCode;
  final String message;
  const SiiApiException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'SiiApiException(${statusCode ?? '-'}): $message';
}

/// Cliente HTTP del backend del SII (TecNM Celaya).
///
/// Endpoints:
///  - POST /api/login                          (público — devuelve JWT)
///  - GET  /api/movil/estudiante               (auth)
///  - GET  /api/movil/estudiante/calificaciones (auth)
///  - GET  /api/movil/estudiante/kardex        (auth)
///  - GET  /api/movil/estudiante/horarios      (auth)
///
/// Todos los métodos `get*` requieren un token JWT obtenido vía [login].
///
/// ── CORS en web ─────────────────────────────────────────────────────────────
/// El servidor del SII no envía `Access-Control-Allow-Origin`, así que el
/// navegador bloquea las requests directas desde Flutter Web. En móvil
/// (Android/iOS) no aplica CORS y la request va directa al SII.
///
/// En web ruteamos por un Cloudflare Worker propio (free tier: 100k req/día)
/// que reenvía 1-a-1 al SII y agrega los headers CORS necesarios. El código
/// del worker está en `infra/cloudflare-worker.js` (o en el dashboard de
/// Cloudflare). Es persistente y bajo nuestro control — a diferencia de
/// corsproxy.io u otros proxies públicos.
///
/// Para rotar el worker (cambiar de cuenta/subdominio) basta con actualizar
/// [_webProxyOrigin]; el resto del cliente no cambia.
class SiiApiService {
  static const String _siiOrigin = 'https://sii.celaya.tecnm.mx/api';

  /// Worker de Cloudflare que actúa como proxy CORS en web. El path
  /// solicitado se concatena tal cual: `/login` → `<origin>/login`.
  static const String _webProxyOrigin =
      'https://tecnm-sii-proxy.axolotljunior274.workers.dev';

  final http.Client _client;
  final Duration _timeout;

  SiiApiService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        // 8s es agresivo a propósito: el peor caso típico del SII vía worker
        // es ~1s; si pasamos 8s casi seguro algo está mal (token rechazado
        // colgado, worker caído, red sin internet) y prefiero fallar rápido
        // para que el usuario pueda reaccionar (reconectar SII, reintentar)
        // en vez de esperar 20s en blanco.
        _timeout = timeout ?? const Duration(seconds: 8);

  void dispose() => _client.close();

  /// Construye la URL final del endpoint. En web pasa por el Cloudflare
  /// Worker; en móvil va directo al SII (no aplica CORS).
  Uri _url(String path) {
    final origin = kIsWeb ? _webProxyOrigin : _siiOrigin;
    return Uri.parse('$origin$path');
  }

  // ─── Autenticación ─────────────────────────────────────────────────────────

  /// Hace login con email institucional y password. Devuelve el JWT a usar
  /// como `Authorization: Bearer <token>` en los demás endpoints.
  Future<SiiLoginResponse> login({
    required String email,
    required String password,
  }) async {
    final res = await _post('/login', body: {'email': email, 'password': password});
    return SiiLoginResponse.fromJson(res);
  }

  // ─── Endpoints autenticados ────────────────────────────────────────────────

  Future<SiiEstudiante> getEstudiante(String token) async {
    final res = await _get('/movil/estudiante', token: token);
    final data = res['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const SiiApiException('Respuesta sin campo `data`');
    }
    return SiiEstudiante.fromJson(data);
  }

  Future<List<SiiPeriodoCalificaciones>> getCalificaciones(String token) async {
    final res = await _get('/movil/estudiante/calificaciones', token: token);
    final list = res['data'] as List?;
    if (list == null) return const [];
    return list
        .cast<Map<String, dynamic>>()
        .map(SiiPeriodoCalificaciones.fromJson)
        .toList();
  }

  Future<SiiKardex> getKardex(String token) async {
    final res = await _get('/movil/estudiante/kardex', token: token);
    final data = res['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const SiiApiException('Respuesta sin campo `data`');
    }
    return SiiKardex.fromJson(data);
  }

  Future<List<SiiPeriodoHorario>> getHorarios(String token) async {
    final res = await _get('/movil/estudiante/horarios', token: token);
    final list = res['data'] as List?;
    if (list == null) return const [];
    return list
        .cast<Map<String, dynamic>>()
        .map(SiiPeriodoHorario.fromJson)
        .toList();
  }

  // ─── Internos ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _request(
      () => _client.post(
        _url(path),
        headers: const {'Content-Type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> _get(String path, {required String token}) {
    return _request(
      () => _client.get(
        _url(path),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    final http.Response res;
    try {
      res = await send().timeout(_timeout);
    } on TimeoutException {
      throw const SiiApiException('Tiempo de espera agotado');
    } catch (e) {
      throw SiiApiException('Error de red: $e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SiiApiException(
        'Sesión expirada o no autorizada',
        statusCode: res.statusCode,
      );
    }

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw SiiApiException(
        'Respuesta no es JSON válido (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = parsed['message'] is String
          ? parsed['message'] as String
          : 'Error ${res.statusCode}';
      throw SiiApiException(msg, statusCode: res.statusCode);
    }

    return parsed;
  }
}
