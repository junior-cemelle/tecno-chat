import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Mapeo consistente calificación → color, compartido por las vistas SII
/// (calificaciones y kárdex). Mantiene una sola semántica visual:
///   <60   rojo            (NA)
///   60-69 naranja          (apenas)
///   70-84 verde claro      (bien)
///   85+   verde fuerte     (excelente)
///   null  gris             (no reportada / cursando)
Color gradeColor(double? grade, {required ColorScheme cs}) {
  if (grade == null) return cs.onSurface.withAlpha(110);
  if (grade < 60) return AppColors.error;
  if (grade < 70) return Colors.orange.shade700;
  if (grade < 85) return AppColors.green;
  return AppColors.greenDark;
}

double? parseGrade(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw);
}

/// Promedio aritmético de las calificaciones que ya tienen valor numérico.
/// Devuelve null si no hay ninguna reportada.
double? averageOf(Iterable<double?> grades) {
  final valid = grades.whereType<double>().toList();
  if (valid.isEmpty) return null;
  return valid.reduce((a, b) => a + b) / valid.length;
}
