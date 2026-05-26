import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/asesoria_models.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

/// Excepción de la capa asesorías con mensaje listo para mostrar al usuario.
class AsesoriaException implements Exception {
  final String message;
  const AsesoriaException(this.message);
  @override
  String toString() => message;
}

/// Lógica de negocio para el flujo completo de asesorías entre alumnos.
///
/// Reglas duras (validadas aquí, NO por la UI):
///  - Solo alumnos pueden solicitar ser asesor.
///  - El alumno debe estar en 4º semestre o superior.
///  - Un alumno puede tener varias asesorías activas, pero solo UNA por materia.
///  - El gerente fija capacidad y semestre al aprobar (no se puede modificar
///    después).
///  - Los cupos consumidos NO se liberan al finalizar la asesoría.
///  - Solo el asesor puede aceptar/rechazar solicitudes de alumnos.
///  - Solo el gerente puede aprobar/rechazar/finalizar asesorías.
class AsesoriaService {
  static const int _minSemestreParaAsesor = 4;

  final FirebaseFirestore _db;
  final StorageService _storage;

  AsesoriaService({
    FirebaseFirestore? firestore,
    required StorageService storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage;

  CollectionReference<Map<String, dynamic>> get _asesorias =>
      _db.collection('asesorias');
  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('asesoria_requests');
  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ─── 1. Asesor: solicitar ser asesor ──────────────────────────────────────

  /// Crea la solicitud (status=pending). El [cvBytes] se sube a Supabase y la
  /// URL resultante se guarda en `cvUrl`.
  ///
  /// Valida:
  ///  - usuario es alumno
  ///  - semestre ≥ 4
  ///  - no tiene otra asesoría ACTIVA (pending/approved/completed) en la misma
  ///    materia
  Future<Asesoria> applyAsAdvisor({
    required UserModel advisor,
    required String materia,
    required String motivos,
    required Uint8List cvBytes,
  }) async {
    if (!advisor.isStudent) {
      throw const AsesoriaException(
          'Solo los alumnos pueden registrarse como asesores.');
    }
    final sem = advisor.semester;
    if (sem == null || sem < _minSemestreParaAsesor) {
      throw const AsesoriaException(
          'Debes cursar al menos 4º semestre para ser asesor.');
    }
    if (materia.trim().isEmpty || motivos.trim().isEmpty) {
      throw const AsesoriaException(
          'Indica la materia y tus motivos para asesorar.');
    }

    // Asesoría activa = no terminal. Bloquea duplicados por materia.
    final activa = await _findActiveAsesoriaForAdvisor(
      advisorUid: advisor.uid,
      materia: materia.trim(),
    );
    if (activa != null) {
      throw const AsesoriaException(
          'Ya tienes una asesoría activa en esa materia.');
    }

    // Subir CV — usamos un key temporal porque aún no tenemos el doc.
    final tempKey =
        '${advisor.uid}_${DateTime.now().millisecondsSinceEpoch}';
    final cvUrl = await _storage.uploadAsesoriaCv(tempKey, cvBytes);

    // Crear doc
    final ref = _asesorias.doc();
    final asesoria = Asesoria(
      id: ref.id,
      advisorUid: advisor.uid,
      materia: materia.trim(),
      motivos: motivos.trim(),
      cvUrl: cvUrl,
      status: AsesoriaStatus.pending,
      createdAt: DateTime.now(),
    );
    await ref.set(asesoria.toMap());
    return asesoria;
  }

  Future<Asesoria?> _findActiveAsesoriaForAdvisor({
    required String advisorUid,
    required String materia,
  }) async {
    final snap = await _asesorias
        .where('advisorUid', isEqualTo: advisorUid)
        .where('materia', isEqualTo: materia)
        .where('status', whereIn: [
      AsesoriaStatus.pending.wire,
      AsesoriaStatus.approved.wire,
      AsesoriaStatus.completed.wire,
    ]).get();
    if (snap.docs.isEmpty) return null;
    return Asesoria.fromDoc(snap.docs.first);
  }

  // ─── 2. Gerente: aprobar / rechazar ────────────────────────────────────────

  /// Aprueba la solicitud. NO crea el chat aquí — se crea perezosamente cuando
  /// el asesor acepta a su primer alumno (en `acceptStudentRequest`). Esto
  /// evita que el gerente tenga que crear un doc en `chats/` (donde las rules
  /// suelen exigir que el creador esté en `participantIds`), y además un chat
  /// con un solo participante no es funcional.
  Future<void> approveAsesoria({
    required UserModel manager,
    required String asesoriaId,
    required int semestreObjetivo,
    required int capacidad,
  }) async {
    if (!manager.isAsesoriaManager) {
      throw const AsesoriaException(
          'Solo el gerente de asesorías puede aprobar solicitudes.');
    }
    if (capacidad < 1) {
      throw const AsesoriaException(
          'La capacidad debe ser al menos 1 alumno.');
    }

    final ref = _asesorias.doc(asesoriaId);
    final asesoria = await _readAsesoria(ref);
    if (asesoria.status != AsesoriaStatus.pending) {
      throw const AsesoriaException(
          'Esta asesoría ya fue revisada anteriormente.');
    }

    await ref.update({
      'status': AsesoriaStatus.approved.wire,
      'managerUid': manager.uid,
      'semestreObjetivo': semestreObjetivo,
      'capacidad': capacidad,
      'reviewedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> rejectAsesoria({
    required UserModel manager,
    required String asesoriaId,
    required String reason,
  }) async {
    if (!manager.isAsesoriaManager) {
      throw const AsesoriaException(
          'Solo el gerente de asesorías puede rechazar solicitudes.');
    }
    final ref = _asesorias.doc(asesoriaId);
    final asesoria = await _readAsesoria(ref);
    if (asesoria.status != AsesoriaStatus.pending) {
      throw const AsesoriaException(
          'Esta asesoría ya fue revisada anteriormente.');
    }
    await ref.update({
      'status': AsesoriaStatus.rejected.wire,
      'managerUid': manager.uid,
      'rejectionReason': reason,
      'reviewedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─── 3. Alumno: solicitar entrar a una asesoría ───────────────────────────

  Future<AsesoriaRequest> requestToJoin({
    required UserModel student,
    required String asesoriaId,
    String? mensaje,
  }) async {
    if (!student.isStudent) {
      throw const AsesoriaException(
          'Solo los alumnos pueden solicitar asesoría.');
    }
    final asesoria = await _readAsesoria(_asesorias.doc(asesoriaId));
    if (asesoria.advisorUid == student.uid) {
      throw const AsesoriaException(
          'No puedes inscribirte en tu propia asesoría.');
    }
    if (!asesoria.status.acceptsRequests) {
      throw const AsesoriaException(
          'Esta asesoría no está aceptando alumnos en este momento.');
    }
    if (asesoria.studentUids.contains(student.uid)) {
      throw const AsesoriaException(
          'Ya eres parte de esta asesoría.');
    }
    if (asesoria.estaLlena) {
      throw const AsesoriaException(
          'La asesoría ya alcanzó su capacidad máxima.');
    }
    // Bloquea solicitudes duplicadas pendientes.
    final dupe = await _requests
        .where('asesoriaId', isEqualTo: asesoriaId)
        .where('studentUid', isEqualTo: student.uid)
        .where('status', isEqualTo: AsesoriaRequestStatus.pending.wire)
        .limit(1)
        .get();
    if (dupe.docs.isNotEmpty) {
      throw const AsesoriaException(
          'Ya tienes una solicitud pendiente en esta asesoría.');
    }

    final ref = _requests.doc();
    final req = AsesoriaRequest(
      id: ref.id,
      asesoriaId: asesoriaId,
      studentUid: student.uid,
      status: AsesoriaRequestStatus.pending,
      mensaje: mensaje?.trim().isEmpty == true ? null : mensaje?.trim(),
      createdAt: DateTime.now(),
    );
    await ref.set(req.toMap());
    return req;
  }

  // ─── 4. Asesor: aceptar / rechazar solicitudes de alumnos ────────────────

  Future<void> acceptStudentRequest({
    required UserModel advisor,
    required String requestId,
  }) async {
    final reqRef = _requests.doc(requestId);
    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) {
      throw const AsesoriaException('La solicitud no existe.');
    }
    final req = AsesoriaRequest.fromDoc(reqSnap);
    if (req.status != AsesoriaRequestStatus.pending) {
      throw const AsesoriaException(
          'Esta solicitud ya fue revisada.');
    }

    final asesoriaRef = _asesorias.doc(req.asesoriaId);
    final asesoria = await _readAsesoria(asesoriaRef);
    if (asesoria.advisorUid != advisor.uid) {
      throw const AsesoriaException(
          'Solo el asesor de esta asesoría puede aceptar alumnos.');
    }
    if (!asesoria.status.acceptsRequests) {
      throw const AsesoriaException(
          'La asesoría ya no acepta alumnos.');
    }
    if (asesoria.estaLlena) {
      throw const AsesoriaException(
          'La asesoría ya está llena. Rechaza esta solicitud o espera.');
    }

    final batch = _db.batch();
    batch.update(reqRef, {
      'status': AsesoriaRequestStatus.accepted.wire,
      'reviewedAt': Timestamp.fromDate(DateTime.now()),
    });

    final asesoriaUpdate = <String, dynamic>{
      'studentUids': FieldValue.arrayUnion([req.studentUid]),
    };

    if (asesoria.chatId == null) {
      // Primer alumno aceptado → creamos el chat de asesoría aquí. El asesor
      // (que es quien está ejecutando este método) figura como participante
      // y creador, así que las rules de creación de chats lo aceptan.
      final chatRef = _chats.doc();
      final chat = ChatModel(
        id: chatRef.id,
        type: ChatType.asesoria,
        participantIds: [asesoria.advisorUid, req.studentUid],
        createdAt: DateTime.now(),
        groupName: 'Asesoría: ${asesoria.materia}',
        createdBy: asesoria.advisorUid,
        adminIds: [asesoria.advisorUid],
        description:
            'Asesoría académica de ${asesoria.materia} '
            '(semestre ${asesoria.semestreObjetivo ?? '-'}, '
            'hasta ${asesoria.capacidad ?? '-'} alumnos)',
        asesoriaId: asesoria.id,
      );
      batch.set(chatRef, chat.toMap());
      asesoriaUpdate['chatId'] = chatRef.id;
    } else {
      // Ya existe el chat: solo agregamos al nuevo alumno como participante.
      batch.update(_chats.doc(asesoria.chatId!), {
        'participantIds': FieldValue.arrayUnion([req.studentUid]),
      });
    }

    batch.update(asesoriaRef, asesoriaUpdate);
    await batch.commit();
  }

  Future<void> rejectStudentRequest({
    required UserModel advisor,
    required String requestId,
  }) async {
    final reqRef = _requests.doc(requestId);
    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) {
      throw const AsesoriaException('La solicitud no existe.');
    }
    final req = AsesoriaRequest.fromDoc(reqSnap);
    if (req.status != AsesoriaRequestStatus.pending) {
      throw const AsesoriaException(
          'Esta solicitud ya fue revisada.');
    }
    final asesoria = await _readAsesoria(_asesorias.doc(req.asesoriaId));
    if (asesoria.advisorUid != advisor.uid) {
      throw const AsesoriaException(
          'Solo el asesor puede rechazar solicitudes.');
    }
    await reqRef.update({
      'status': AsesoriaRequestStatus.rejected.wire,
      'reviewedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─── 5. Cierre: completar (asesor) → finalizar (gerente) ─────────────────

  Future<void> markCompleted({
    required UserModel advisor,
    required String asesoriaId,
  }) async {
    final ref = _asesorias.doc(asesoriaId);
    final asesoria = await _readAsesoria(ref);
    if (asesoria.advisorUid != advisor.uid) {
      throw const AsesoriaException(
          'Solo el asesor puede marcar la asesoría como completada.');
    }
    if (asesoria.status != AsesoriaStatus.approved) {
      throw const AsesoriaException(
          'La asesoría debe estar activa para marcarla como completada.');
    }
    await ref.update({
      'status': AsesoriaStatus.completed.wire,
      'completedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> finalize({
    required UserModel manager,
    required String asesoriaId,
  }) async {
    if (!manager.isAsesoriaManager) {
      throw const AsesoriaException(
          'Solo el gerente puede finalizar asesorías.');
    }
    final ref = _asesorias.doc(asesoriaId);
    final asesoria = await _readAsesoria(ref);
    if (asesoria.status != AsesoriaStatus.completed) {
      throw const AsesoriaException(
          'La asesoría debe estar marcada como completada antes de finalizar.');
    }
    await ref.update({
      'status': AsesoriaStatus.finalized.wire,
      'finalizedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─── Reads (one-shot, no streams; los streams viven en el provider) ──────

  Future<Asesoria> _readAsesoria(
      DocumentReference<Map<String, dynamic>> ref) async {
    final snap = await ref.get();
    if (!snap.exists) {
      throw const AsesoriaException('La asesoría no existe.');
    }
    return Asesoria.fromDoc(snap);
  }

  // ─── Queries reutilizables por los providers ──────────────────────────────

  // NOTA SOBRE ORDENAMIENTO ────────────────────────────────────────────────
  // Combinar `where(...)` con `orderBy(...)` sobre campos distintos requiere
  // un índice compuesto por cada combinación en Firestore. Para no tener que
  // crear/mantener ~5 índices manualmente para datos de bajo volumen
  // (asesorías activas siempre son pocas), las queries devuelven SIN
  // ordenamiento y los providers ordenan client-side.

  Query<Map<String, dynamic>> pendingAsesoriasQuery() {
    return _asesorias
        .where('status', isEqualTo: AsesoriaStatus.pending.wire);
  }

  /// Asesorías que el gerente debe finalizar (completadas, esperando visto
  /// bueno).
  Query<Map<String, dynamic>> awaitingFinalizationQuery() {
    return _asesorias
        .where('status', isEqualTo: AsesoriaStatus.completed.wire);
  }

  /// Todas las asesorías donde un usuario es el asesor.
  Query<Map<String, dynamic>> asesoriasByAdvisor(String advisorUid) {
    return _asesorias.where('advisorUid', isEqualTo: advisorUid);
  }

  /// Asesorías disponibles para buscar (approved + con cupo). El filtro de
  /// cupo se aplica client-side porque Firestore no permite combinar where
  /// con expresiones derivadas.
  Query<Map<String, dynamic>> availableAsesoriasByMateria(String materia) {
    return _asesorias
        .where('status', isEqualTo: AsesoriaStatus.approved.wire)
        .where('materia', isEqualTo: materia);
  }

  /// Todas las asesorías approved (para listado libre, filtrado client-side).
  Query<Map<String, dynamic>> allApprovedAsesorias() {
    return _asesorias
        .where('status', isEqualTo: AsesoriaStatus.approved.wire);
  }

  /// Asesorías donde un alumno fue aceptado.
  Query<Map<String, dynamic>> asesoriasForStudent(String studentUid) {
    return _asesorias.where('studentUids', arrayContains: studentUid);
  }

  /// Solicitudes pendientes en una asesoría (las que el asesor debe revisar).
  Query<Map<String, dynamic>> pendingRequestsForAsesoria(String asesoriaId) {
    return _requests
        .where('asesoriaId', isEqualTo: asesoriaId)
        .where('status', isEqualTo: AsesoriaRequestStatus.pending.wire);
  }

  /// Solicitudes que un alumno ha enviado.
  Query<Map<String, dynamic>> requestsByStudent(String studentUid) {
    return _requests.where('studentUid', isEqualTo: studentUid);
  }

  // ─── Convenience: lookup de usuarios para mostrar nombres en UI ──────────

  Future<UserModel?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromDoc(doc);
  }
}
