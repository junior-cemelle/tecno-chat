import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sii_models.dart';
import '../data/services/sii_api_service.dart';
import 'auth_provider.dart';

/// Lanzada cuando el storage no tiene token (o ya expiró y se descartó).
/// La UI debe ofrecer al usuario cerrar sesión y reingresar credenciales.
class SiiSessionExpiredException implements Exception {
  const SiiSessionExpiredException();
  @override
  String toString() =>
      'Tu sesión del SII expiró. Cierra sesión y vuelve a iniciar.';
}

String _requireToken(Ref ref) {
  final token = ref.read(siiTokenStorageProvider).readToken();
  if (token == null) throw const SiiSessionExpiredException();
  return token;
}

/// Wrapper común: ejecuta la llamada con el token y, ante un 401/403, limpia
/// el JWT persistido para que el siguiente intento muera inmediato con
/// `SiiSessionExpiredException` en vez de volver a tardar el timeout entero.
///
/// También observa `authStateProvider` para que los providers SII se
/// re-ejecuten cuando cambia el usuario (login/logout). Sin esa subscripción
/// el cache `AsyncError(SessionExpired)` del usuario anterior persistiría
/// hasta el próximo `invalidate` manual.
Future<T> _withSession<T>(
  Ref ref,
  Future<T> Function(String token) call,
) async {
  // IMPORTANTE: el watch debe registrarse ANTES del primer await — si no,
  // Riverpod no lo cuenta como dependencia reactiva.
  ref.watch(authStateProvider);
  final token = _requireToken(ref);
  try {
    return await call(token);
  } on SiiApiException catch (e) {
    if (e.isUnauthorized) {
      await ref.read(siiTokenStorageProvider).clearToken();
    }
    rethrow;
  }
}

/// `GET /api/movil/estudiante` — dashboard académico del alumno.
final siiEstudianteProvider = FutureProvider<SiiEstudiante>((ref) async {
  return _withSession(ref,
      (t) => ref.read(siiApiServiceProvider).getEstudiante(t));
});

/// `GET /api/movil/estudiante/calificaciones` — por periodo.
final siiCalificacionesProvider =
    FutureProvider<List<SiiPeriodoCalificaciones>>((ref) async {
  return _withSession(ref,
      (t) => ref.read(siiApiServiceProvider).getCalificaciones(t));
});

/// `GET /api/movil/estudiante/kardex` — historial completo.
final siiKardexProvider = FutureProvider<SiiKardex>((ref) async {
  return _withSession(ref,
      (t) => ref.read(siiApiServiceProvider).getKardex(t));
});

/// `GET /api/movil/estudiante/horarios` — clases por periodo.
final siiHorariosProvider =
    FutureProvider<List<SiiPeriodoHorario>>((ref) async {
  return _withSession(ref,
      (t) => ref.read(siiApiServiceProvider).getHorarios(t));
});
