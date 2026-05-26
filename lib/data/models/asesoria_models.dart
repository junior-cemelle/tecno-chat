import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Estado de una asesoría ─────────────────────────────────────────────────

/// Ciclo de vida de una asesoría:
///
/// ```
///  pending  ──aprobar──▶  approved  ──asesor completa──▶  completed
///     │                       │                              │
///     └──rechazar──▶ rejected │                              │
///                             └─────────────────finalize─────┘
///                                          ▼
///                                      finalized   (terminal)
/// ```
///
/// - pending: el alumno-asesor envió la solicitud, esperando revisión del
///   gerente.
/// - approved: el gerente aprobó. Capacidad y semestre están fijos. El chat
///   está creado y el asesor puede recibir solicitudes de alumnos.
/// - rejected: el gerente rechazó. Terminal.
/// - completed: el asesor marcó la asesoría como terminada, esperando el
///   visto bueno del gerente.
/// - finalized: el gerente confirmó. Terminal. El chat ya no recibe nuevos
///   alumnos. (Por diseño, "el número de asesorías del asesor se queda igual"
///   → los cupos consumidos no se liberan.)
enum AsesoriaStatus { pending, approved, rejected, completed, finalized }

/// Helpers para serializar/deserializar enum ↔ string Firestore.
extension AsesoriaStatusX on AsesoriaStatus {
  String get wire => name;
  bool get isTerminal =>
      this == AsesoriaStatus.rejected || this == AsesoriaStatus.finalized;
  bool get acceptsRequests => this == AsesoriaStatus.approved;
}

AsesoriaStatus _asesoriaStatusFrom(String? raw) {
  return AsesoriaStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => AsesoriaStatus.pending,
  );
}

// ─── Asesoría (la oferta del asesor) ────────────────────────────────────────

class Asesoria {
  final String id;
  final String advisorUid;

  // Datos de la solicitud original
  final String materia;
  final String motivos;
  final String cvUrl; // URL en Supabase Storage

  // Datos seteados al aprobar
  final AsesoriaStatus status;
  final String? managerUid;
  final int? semestreObjetivo;
  final int? capacidad;
  final String? rejectionReason;

  // Lista actual de alumnos aceptados en la asesoría
  final List<String> studentUids;

  // Chat grupal vinculado (se crea al aprobar)
  final String? chatId;

  // Timeline
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final DateTime? completedAt;
  final DateTime? finalizedAt;

  const Asesoria({
    required this.id,
    required this.advisorUid,
    required this.materia,
    required this.motivos,
    required this.cvUrl,
    required this.status,
    this.managerUid,
    this.semestreObjetivo,
    this.capacidad,
    this.rejectionReason,
    this.studentUids = const [],
    this.chatId,
    required this.createdAt,
    this.reviewedAt,
    this.completedAt,
    this.finalizedAt,
  });

  /// Cupos restantes hasta llenar la capacidad. null si aún no aprobada.
  /// Importante: los cupos NO se liberan al completar/finalizar; los slots
  /// consumidos siguen consumidos por diseño.
  int? get cuposDisponibles {
    if (capacidad == null) return null;
    return (capacidad! - studentUids.length).clamp(0, capacidad!);
  }

  bool get estaLlena =>
      capacidad != null && studentUids.length >= capacidad!;

  factory Asesoria.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Asesoria(
      id: doc.id,
      advisorUid: d['advisorUid'] ?? '',
      materia: d['materia'] ?? '',
      motivos: d['motivos'] ?? '',
      cvUrl: d['cvUrl'] ?? '',
      status: _asesoriaStatusFrom(d['status'] as String?),
      managerUid: d['managerUid'] as String?,
      semestreObjetivo: d['semestreObjetivo'] as int?,
      capacidad: d['capacidad'] as int?,
      rejectionReason: d['rejectionReason'] as String?,
      studentUids: List<String>.from(d['studentUids'] ?? []),
      chatId: d['chatId'] as String?,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      finalizedAt: (d['finalizedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'advisorUid': advisorUid,
        'materia': materia,
        'motivos': motivos,
        'cvUrl': cvUrl,
        'status': status.wire,
        if (managerUid != null) 'managerUid': managerUid,
        if (semestreObjetivo != null) 'semestreObjetivo': semestreObjetivo,
        if (capacidad != null) 'capacidad': capacidad,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'studentUids': studentUids,
        if (chatId != null) 'chatId': chatId,
        'createdAt': Timestamp.fromDate(createdAt),
        if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
        if (completedAt != null)
          'completedAt': Timestamp.fromDate(completedAt!),
        if (finalizedAt != null)
          'finalizedAt': Timestamp.fromDate(finalizedAt!),
      };
}

// ─── Solicitud de alumno para unirse a una asesoría ─────────────────────────

enum AsesoriaRequestStatus { pending, accepted, rejected }

extension AsesoriaRequestStatusX on AsesoriaRequestStatus {
  String get wire => name;
}

AsesoriaRequestStatus _requestStatusFrom(String? raw) {
  return AsesoriaRequestStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => AsesoriaRequestStatus.pending,
  );
}

/// Solicitud de un alumno para ser aceptado como consultante en una asesoría.
/// Una vez aceptada, el alumno se agrega a `Asesoria.studentUids` y al
/// `participantIds` del chat. La solicitud queda en `accepted` como registro
/// histórico.
class AsesoriaRequest {
  final String id;
  final String asesoriaId;
  final String studentUid;
  final AsesoriaRequestStatus status;
  final String? mensaje; // mensaje opcional del alumno al solicitar
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const AsesoriaRequest({
    required this.id,
    required this.asesoriaId,
    required this.studentUid,
    required this.status,
    this.mensaje,
    required this.createdAt,
    this.reviewedAt,
  });

  factory AsesoriaRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AsesoriaRequest(
      id: doc.id,
      asesoriaId: d['asesoriaId'] ?? '',
      studentUid: d['studentUid'] ?? '',
      status: _requestStatusFrom(d['status'] as String?),
      mensaje: d['mensaje'] as String?,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'asesoriaId': asesoriaId,
        'studentUid': studentUid,
        'status': status.wire,
        if (mensaje != null) 'mensaje': mensaje,
        'createdAt': Timestamp.fromDate(createdAt),
        if (reviewedAt != null)
          'reviewedAt': Timestamp.fromDate(reviewedAt!),
      };
}
