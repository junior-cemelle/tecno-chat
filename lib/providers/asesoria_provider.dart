import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/asesoria_models.dart';
import '../data/services/asesoria_service.dart';
import '../data/services/storage_service.dart';

/// Service singleton — sin dependencias volátiles, vive toda la sesión.
/// Sigue el patrón del resto del proyecto: `StorageService()` se instancia
/// directamente en vez de pasar por un provider (es un wrapper sin estado).
final asesoriaServiceProvider = Provider<AsesoriaService>((ref) {
  return AsesoriaService(storage: StorageService());
});

// Helpers de ordenamiento client-side ───────────────────────────────────────
// Las queries vienen sin orderBy para evitar índices compuestos en Firestore
// (ver nota en AsesoriaService). Ordenamos aquí, antes de exponer a la UI.

List<Asesoria> _sortByCreatedAtAsc(List<Asesoria> list) {
  list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return list;
}

List<Asesoria> _sortByCreatedAtDesc(List<Asesoria> list) {
  list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
}

List<Asesoria> _sortByCompletedAtAsc(List<Asesoria> list) {
  list.sort((a, b) {
    // completedAt no debería ser null en este stream, pero defensivo.
    final ac = a.completedAt ?? a.createdAt;
    final bc = b.completedAt ?? b.createdAt;
    return ac.compareTo(bc);
  });
  return list;
}

List<AsesoriaRequest> _sortRequestsByCreatedAtAsc(
    List<AsesoriaRequest> list) {
  list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return list;
}

List<AsesoriaRequest> _sortRequestsByCreatedAtDesc(
    List<AsesoriaRequest> list) {
  list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
}

// ─── Streams para el gerente ────────────────────────────────────────────────

/// Solicitudes pendientes de aprobar (status=pending). El gerente las ve en
/// su dashboard.
final pendingAsesoriasProvider = StreamProvider<List<Asesoria>>((ref) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.pendingAsesoriasQuery().snapshots().map(
      (s) => _sortByCreatedAtAsc(s.docs.map(Asesoria.fromDoc).toList()));
});

/// Asesorías que el asesor marcó como completadas y esperan finalización.
final awaitingFinalizationProvider =
    StreamProvider<List<Asesoria>>((ref) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.awaitingFinalizationQuery().snapshots().map(
      (s) => _sortByCompletedAtAsc(s.docs.map(Asesoria.fromDoc).toList()));
});

// ─── Streams para el asesor ────────────────────────────────────────────────

/// Todas las asesorías donde [advisorUid] es el asesor (cualquier status).
final asesoriasByAdvisorProvider =
    StreamProvider.family<List<Asesoria>, String>((ref, advisorUid) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.asesoriasByAdvisor(advisorUid).snapshots().map(
      (s) => _sortByCreatedAtDesc(s.docs.map(Asesoria.fromDoc).toList()));
});

/// Solicitudes pendientes que el asesor debe revisar en una asesoría dada.
final pendingRequestsForAsesoriaProvider =
    StreamProvider.family<List<AsesoriaRequest>, String>((ref, asesoriaId) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.pendingRequestsForAsesoria(asesoriaId).snapshots().map((s) =>
      _sortRequestsByCreatedAtAsc(
          s.docs.map(AsesoriaRequest.fromDoc).toList()));
});

// ─── Streams para el alumno consultante ────────────────────────────────────

/// Asesorías donde el alumno fue aceptado (sus consultorías activas).
final asesoriasForStudentProvider =
    StreamProvider.family<List<Asesoria>, String>((ref, studentUid) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.asesoriasForStudent(studentUid).snapshots().map(
      (s) => _sortByCreatedAtDesc(s.docs.map(Asesoria.fromDoc).toList()));
});

/// Historial de solicitudes que un alumno ha enviado.
final requestsByStudentProvider =
    StreamProvider.family<List<AsesoriaRequest>, String>((ref, studentUid) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.requestsByStudent(studentUid).snapshots().map((s) =>
      _sortRequestsByCreatedAtDesc(
          s.docs.map(AsesoriaRequest.fromDoc).toList()));
});

// ─── Búsqueda libre (cualquier alumno) ──────────────────────────────────────

/// Todas las asesorías approved. Filtrado por materia y por cupo se hace
/// client-side en la pantalla de búsqueda.
final approvedAsesoriasProvider = StreamProvider<List<Asesoria>>((ref) {
  final svc = ref.watch(asesoriaServiceProvider);
  return svc.allApprovedAsesorias().snapshots().map(
      (s) => _sortByCreatedAtDesc(s.docs.map(Asesoria.fromDoc).toList()));
});
