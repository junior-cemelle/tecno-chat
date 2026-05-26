import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { student, teacher }

/// Perfil del usuario almacenado en Firestore.
///
/// Filosofía de datos:
///  - Para alumnos: `numeroControl`, `displayName`, `email` y `avatarUrl`
///    se snapshotean del SII al registrarse. El resto (calificaciones, kárdex,
///    horarios, promedios) NO se guarda — se consulta on-demand al backend SII
///    usando el JWT vigente en sesión.
///  - Para profesores: campos llenados manualmente (no conectan al SII).
///  - `phone` se vincula DESPUÉS del registro (opcional al crear el perfil).
class UserModel {
  final String uid;
  /// Teléfono verificado (puede estar vacío si aún no se vinculó tras registro)
  final String phone;
  final String email;
  final String displayName;
  final String avatarUrl;
  final UserRole role;

  /// Número de control del alumno (solo aplica a `role == student`).
  /// Es la llave para refrescar datos del SII en cualquier momento.
  final String? numeroControl;

  final String career;
  final int? semester; // solo alumnos
  final String? department; // solo profesores

  /// Solo aplica a teachers. Marca a este profesor como GERENTE DE ASESORÍAS:
  /// puede revisar solicitudes de alumnos para ser asesores, finalizar
  /// asesorías completadas y supervisar los chats. Se setea manualmente en
  /// Firestore Console (no hay UI para promover gerentes — es admin).
  final bool isAsesoriaManager;

  final bool isOnline;
  final DateTime lastSeen;
  final List<String> contactIds;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.phone,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.role,
    this.numeroControl,
    required this.career,
    this.semester,
    this.department,
    this.isAsesoriaManager = false,
    required this.isOnline,
    required this.lastSeen,
    required this.contactIds,
    required this.createdAt,
  });

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final lastSeenTimestamp = d['lastSeen'] is Timestamp ? d['lastSeen'] as Timestamp : null;
    final createdAtTimestamp = d['createdAt'] is Timestamp ? d['createdAt'] as Timestamp : null;

    return UserModel(
      uid: doc.id,
      phone: d['phone'] ?? '',
      email: d['email'] ?? '',
      displayName: d['displayName'] ?? '',
      avatarUrl: d['avatarUrl'] ?? '',
      role: d['role'] == 'teacher' ? UserRole.teacher : UserRole.student,
      numeroControl: d['numeroControl'] as String?,
      career: d['career'] ?? '',
      semester: d['semester'],
      department: d['department'],
      isAsesoriaManager: d['isAsesoriaManager'] ?? false,
      isOnline: d['isOnline'] ?? false,
      lastSeen: lastSeenTimestamp?.toDate() ?? DateTime.now(),
      contactIds: List<String>.from(d['contactIds'] ?? []),
      createdAt: createdAtTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'email': email,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'role': role.name,
        if (numeroControl != null) 'numeroControl': numeroControl,
        'career': career,
        'semester': semester,
        'department': department,
        if (isAsesoriaManager) 'isAsesoriaManager': true,
        'isOnline': isOnline,
        'lastSeen': Timestamp.fromDate(lastSeen),
        'contactIds': contactIds,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  bool get isTeacher => role == UserRole.teacher;
  bool get isStudent => role == UserRole.student;

  /// True si el usuario ya tiene un teléfono verificado vinculado a su cuenta.
  /// El registro inicial puede no incluirlo (se vincula después).
  bool get hasLinkedPhone => phone.isNotEmpty;

  UserModel copyWith({
    String? phone,
    String? email,
    String? displayName,
    String? avatarUrl,
    UserRole? role,
    String? numeroControl,
    String? career,
    int? semester,
    String? department,
    bool? isAsesoriaManager,
    bool? isOnline,
    DateTime? lastSeen,
    List<String>? contactIds,
  }) {
    return UserModel(
      uid: uid,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      numeroControl: numeroControl ?? this.numeroControl,
      career: career ?? this.career,
      semester: semester ?? this.semester,
      department: department ?? this.department,
      isAsesoriaManager: isAsesoriaManager ?? this.isAsesoriaManager,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      contactIds: contactIds ?? this.contactIds,
      createdAt: createdAt,
    );
  }
}
