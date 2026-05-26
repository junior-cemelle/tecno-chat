// Modelos de respuesta del backend del SII (TecNM Celaya):
// https://sii.celaya.tecnm.mx/api/
//
// Estos modelos NO se persisten en Firestore — son DTOs que mapean las
// respuestas JSON del backend. Solo `numeroControl`, `persona`, `email` y
// `foto` se proyectan a `UserModel` para guardarse en Firestore. El resto
// (kárdex, calificaciones, horarios, promedios) se consume on-demand
// usando el JWT como autenticación.

// ─── Login ───────────────────────────────────────────────────────────────────

/// Respuesta de `POST /api/login`.
///
/// Estructura real (el `token` viene anidado en `message.login.token`):
/// ```json
/// {
///   "responseCodeTxt": "...",
///   "message": { "login": { "token": "JWT" } },
///   "status": 200,
///   "flag": "...",
///   "data": 0,
///   "type": "..."
/// }
/// ```
class SiiLoginResponse {
  final String token;
  final int status;
  final String responseCodeTxt;

  const SiiLoginResponse({
    required this.token,
    required this.status,
    required this.responseCodeTxt,
  });

  factory SiiLoginResponse.fromJson(Map<String, dynamic> json) {
    final message = json['message'] as Map<String, dynamic>?;
    final login = message?['login'] as Map<String, dynamic>?;
    final token = login?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Login response sin token');
    }
    return SiiLoginResponse(
      token: token,
      status: (json['status'] as num?)?.toInt() ?? 0,
      responseCodeTxt: json['responseCodeTxt'] as String? ?? '',
    );
  }
}

// ─── Estudiante ──────────────────────────────────────────────────────────────

/// Datos del alumno devueltos por `GET /api/movil/estudiante`.
///
/// Los campos numéricos vienen como string en algunos casos (peculiaridad del
/// backend), los conservamos así para no perder precisión.
class SiiEstudiante {
  final String numeroControl;
  final String persona; // nombre completo
  final String email;
  final int semestre;
  final String foto;

  // Métricas académicas (se consumen on-demand; no se persisten)
  final String numMatRepNoAcreditadas;
  final String creditosAcumulados;
  final String promedioPonderado;
  final String promedioAritmetico;
  final String materiasCursadas;
  final String materiasReprobadas;
  final String materiasAprobadas;
  final int creditosComplementarios;
  final double porcentajeAvance;
  final String? numMateriasRepPrimera;
  final String? numMateriasRepSegunda;
  final double porcentajeAvanceCursando;

  const SiiEstudiante({
    required this.numeroControl,
    required this.persona,
    required this.email,
    required this.semestre,
    required this.foto,
    required this.numMatRepNoAcreditadas,
    required this.creditosAcumulados,
    required this.promedioPonderado,
    required this.promedioAritmetico,
    required this.materiasCursadas,
    required this.materiasReprobadas,
    required this.materiasAprobadas,
    required this.creditosComplementarios,
    required this.porcentajeAvance,
    this.numMateriasRepPrimera,
    this.numMateriasRepSegunda,
    required this.porcentajeAvanceCursando,
  });

  factory SiiEstudiante.fromJson(Map<String, dynamic> json) {
    return SiiEstudiante(
      numeroControl: json['numero_control'] as String? ?? '',
      persona: json['persona'] as String? ?? '',
      email: json['email'] as String? ?? '',
      semestre: (json['semestre'] as num?)?.toInt() ?? 0,
      foto: json['foto'] as String? ?? '',
      numMatRepNoAcreditadas:
          json['num_mat_rep_no_acreditadas'] as String? ?? '',
      creditosAcumulados: json['creditos_acumulados'] as String? ?? '',
      promedioPonderado: json['promedio_ponderado'] as String? ?? '',
      promedioAritmetico: json['promedio_aritmetico'] as String? ?? '',
      materiasCursadas: json['materias_cursadas'] as String? ?? '',
      materiasReprobadas: json['materias_reprobadas'] as String? ?? '',
      materiasAprobadas: json['materias_aprobadas'] as String? ?? '',
      creditosComplementarios:
          (json['creditos_complementarios'] as num?)?.toInt() ?? 0,
      porcentajeAvance:
          (json['porcentaje_avance'] as num?)?.toDouble() ?? 0.0,
      numMateriasRepPrimera: json['num_materias_rep_primera'] as String?,
      numMateriasRepSegunda: json['num_materias_rep_segunda'] as String?,
      porcentajeAvanceCursando:
          (json['percentaje_avance_cursando'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ─── Calificaciones ──────────────────────────────────────────────────────────

class SiiCalificacion {
  final int idCalificacion;
  final int numeroCalificacion;
  final String? calificacion; // puede venir null si aún no se reporta

  const SiiCalificacion({
    required this.idCalificacion,
    required this.numeroCalificacion,
    this.calificacion,
  });

  factory SiiCalificacion.fromJson(Map<String, dynamic> json) {
    return SiiCalificacion(
      idCalificacion: (json['id_calificacion'] as num?)?.toInt() ?? 0,
      numeroCalificacion:
          (json['numero_calificacion'] as num?)?.toInt() ?? 0,
      calificacion: json['calificacion'] as String?,
    );
  }
}

class SiiMateria {
  final int idGrupo;
  final String nombreMateria;
  final String claveMateria;
  final String letraGrupo;
  final List<SiiCalificacion> calificaciones;

  const SiiMateria({
    required this.idGrupo,
    required this.nombreMateria,
    required this.claveMateria,
    required this.letraGrupo,
    required this.calificaciones,
  });

  factory SiiMateria.fromJson(Map<String, dynamic> json) {
    final materia = json['materia'] as Map<String, dynamic>? ?? const {};
    // OJO: el backend tiene typo — "calificaiones" (sin la 'c'). Lo respetamos.
    final califs = (json['calificaiones'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(SiiCalificacion.fromJson)
            .toList() ??
        const [];
    return SiiMateria(
      idGrupo: (materia['id_grupo'] as num?)?.toInt() ?? 0,
      nombreMateria: materia['nombre_materia'] as String? ?? '',
      claveMateria: materia['clave_materia'] as String? ?? '',
      letraGrupo: materia['letra_grupo'] as String? ?? '',
      calificaciones: califs,
    );
  }
}

class SiiPeriodo {
  final String clavePeriodo;
  final int anio;
  final String descripcionPeriodo;

  const SiiPeriodo({
    required this.clavePeriodo,
    required this.anio,
    required this.descripcionPeriodo,
  });

  factory SiiPeriodo.fromJson(Map<String, dynamic> json) {
    return SiiPeriodo(
      clavePeriodo: json['clave_periodo'] as String? ?? '',
      anio: (json['anio'] as num?)?.toInt() ?? 0,
      descripcionPeriodo: json['descripcion_periodo'] as String? ?? '',
    );
  }
}

class SiiPeriodoCalificaciones {
  final SiiPeriodo periodo;
  final List<SiiMateria> materias;

  const SiiPeriodoCalificaciones({
    required this.periodo,
    required this.materias,
  });

  factory SiiPeriodoCalificaciones.fromJson(Map<String, dynamic> json) {
    return SiiPeriodoCalificaciones(
      periodo: SiiPeriodo.fromJson(
          json['periodo'] as Map<String, dynamic>? ?? const {}),
      materias: (json['materias'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map(SiiMateria.fromJson)
              .toList() ??
          const [],
    );
  }
}

// ─── Kárdex ──────────────────────────────────────────────────────────────────

class SiiKardexItem {
  final String nombreMateria;
  final String claveMateria;
  final String periodo;
  final String creditos;
  final String calificacion;
  final String descripcion;
  final int semestre;

  const SiiKardexItem({
    required this.nombreMateria,
    required this.claveMateria,
    required this.periodo,
    required this.creditos,
    required this.calificacion,
    required this.descripcion,
    required this.semestre,
  });

  factory SiiKardexItem.fromJson(Map<String, dynamic> json) {
    return SiiKardexItem(
      nombreMateria: json['nombre_materia'] as String? ?? '',
      claveMateria: json['clave_materia'] as String? ?? '',
      periodo: json['periodo'] as String? ?? '',
      creditos: json['creditos'] as String? ?? '',
      calificacion: json['calificacion'] as String? ?? '',
      descripcion: json['descripcion'] as String? ?? '',
      semestre: (json['semestre'] as num?)?.toInt() ?? 0,
    );
  }
}

class SiiKardex {
  final double porcentajeAvance;
  final List<SiiKardexItem> kardex;

  const SiiKardex({required this.porcentajeAvance, required this.kardex});

  factory SiiKardex.fromJson(Map<String, dynamic> json) {
    return SiiKardex(
      porcentajeAvance: (json['porcentaje_avance'] as num?)?.toDouble() ?? 0.0,
      kardex: (json['kardex'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map(SiiKardexItem.fromJson)
              .toList() ??
          const [],
    );
  }
}

// ─── Horarios ────────────────────────────────────────────────────────────────

class SiiHorarioItem {
  final int idGrupo;
  final String letraGrupo;
  final String nombreMateria;
  final String claveMateria;
  final String claveTurno;
  final String nombrePlan;
  final String letraNivel;
  // Cada día: rango horario "07:00-08:00" o null si no hay clase
  final String? lunes;
  final String? lunesClaveSalon;
  final String? martes;
  final String? martesClaveSalon;
  final String? miercoles;
  final String? miercolesClaveSalon;
  final String? jueves;
  final String? juevesClaveSalon;
  final String? viernes;
  final String? viernesClaveSalon;
  final String? sabado;
  final String? sabadoClaveSalon;

  const SiiHorarioItem({
    required this.idGrupo,
    required this.letraGrupo,
    required this.nombreMateria,
    required this.claveMateria,
    required this.claveTurno,
    required this.nombrePlan,
    required this.letraNivel,
    this.lunes,
    this.lunesClaveSalon,
    this.martes,
    this.martesClaveSalon,
    this.miercoles,
    this.miercolesClaveSalon,
    this.jueves,
    this.juevesClaveSalon,
    this.viernes,
    this.viernesClaveSalon,
    this.sabado,
    this.sabadoClaveSalon,
  });

  factory SiiHorarioItem.fromJson(Map<String, dynamic> json) {
    return SiiHorarioItem(
      idGrupo: (json['id_grupo'] as num?)?.toInt() ?? 0,
      letraGrupo: json['letra_grupo'] as String? ?? '',
      nombreMateria: json['nombre_materia'] as String? ?? '',
      claveMateria: json['clave_materia'] as String? ?? '',
      claveTurno: json['clave_turno'] as String? ?? '',
      nombrePlan: json['nombre_plan'] as String? ?? '',
      letraNivel: json['letra_nivel'] as String? ?? '',
      lunes: json['lunes'] as String?,
      lunesClaveSalon: json['lunes_clave_salon'] as String?,
      martes: json['martes'] as String?,
      martesClaveSalon: json['martes_clave_salon'] as String?,
      miercoles: json['miercoles'] as String?,
      miercolesClaveSalon: json['miercoles_clave_salon'] as String?,
      jueves: json['jueves'] as String?,
      juevesClaveSalon: json['jueves_clave_salon'] as String?,
      viernes: json['viernes'] as String?,
      viernesClaveSalon: json['viernes_clave_salon'] as String?,
      sabado: json['sabado'] as String?,
      sabadoClaveSalon: json['sabado_clave_salon'] as String?,
    );
  }
}

class SiiPeriodoHorario {
  final SiiPeriodo periodo;
  final List<SiiHorarioItem> horario;

  const SiiPeriodoHorario({required this.periodo, required this.horario});

  factory SiiPeriodoHorario.fromJson(Map<String, dynamic> json) {
    return SiiPeriodoHorario(
      periodo: SiiPeriodo.fromJson(
          json['periodo'] as Map<String, dynamic>? ?? const {}),
      horario: (json['horario'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map(SiiHorarioItem.fromJson)
              .toList() ??
          const [],
    );
  }
}
