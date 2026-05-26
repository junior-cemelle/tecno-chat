import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/sii_models.dart';
import '../../providers/sii_provider.dart';
import 'sii_error_view.dart';
import 'sii_grade_colors.dart';

/// `GET /api/movil/estudiante/kardex` — historial completo agrupado por
/// semestre. Cada `ExpansionTile` muestra promedio, totales y desglose
/// de materias del semestre.
class SiiKardexScreen extends ConsumerWidget {
  const SiiKardexScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(siiKardexProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kárdex'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(siiKardexProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (e, _) => SiiErrorView(
          error: e,
          onRetry: () => ref.invalidate(siiKardexProvider),
        ),
        data: (kardex) {
          if (kardex.kardex.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No tienes materias registradas en tu kárdex.',
                  style: GoogleFonts.poppins(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _Body(kardex: kardex);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final SiiKardex kardex;
  const _Body({required this.kardex});

  @override
  Widget build(BuildContext context) {
    // Agrupar por semestre (preservando el orden de aparición).
    final bySemester = <int, List<SiiKardexItem>>{};
    for (final item in kardex.kardex) {
      bySemester.putIfAbsent(item.semestre, () => []).add(item);
    }
    final orderedSems = bySemester.keys.toList()..sort();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _SummaryHeader(
              porcentajeAvance: kardex.porcentajeAvance,
              items: kardex.kardex,
            ),
            const SizedBox(height: 16),
            for (final sem in orderedSems) ...[
              _SemestreSection(
                semestre: sem,
                items: bySemester[sem]!,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Cabecera con resumen global ─────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final double porcentajeAvance;
  final List<SiiKardexItem> items;
  const _SummaryHeader({
    required this.porcentajeAvance,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final aprobadas =
        items.where((i) => (parseGrade(i.calificacion) ?? 0) >= 70).length;
    final reprobadas = items.length - aprobadas;
    final allGrades = items.map((i) => parseGrade(i.calificacion)).toList();
    final globalAvg = averageOf(allGrades);
    final totalCreditos = items.fold<double>(
      0,
      (sum, i) => sum + (double.tryParse(i.creditos) ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withAlpha(220),
            AppColors.greenDark.withAlpha(220),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_edu_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                'Historial académico',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Barra de avance
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (porcentajeAvance / 100).clamp(0, 1),
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${porcentajeAvance.toStringAsFixed(1)}% del plan completado',
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.white.withAlpha(220)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeaderStat(
                  label: 'Materias',
                  value: '${items.length}',
                  icon: Icons.menu_book_outlined),
              _HeaderStat(
                  label: 'Créditos',
                  value: totalCreditos.toStringAsFixed(0),
                  icon: Icons.workspace_premium_outlined),
              _HeaderStat(
                  label: 'Promedio',
                  value:
                      globalAvg == null ? '—' : globalAvg.toStringAsFixed(1),
                  icon: Icons.show_chart_rounded),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _HeaderBadge(
                  color: AppColors.green,
                  label: 'Aprobadas · $aprobadas'),
              const SizedBox(width: 8),
              _HeaderBadge(
                  color: AppColors.error,
                  label: 'Reprobadas · $reprobadas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeaderStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withAlpha(200), size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 10.5, color: Colors.white.withAlpha(200))),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final Color color;
  final String label;
  const _HeaderBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(180), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white),
      ),
    );
  }
}

// ── Sección por semestre ────────────────────────────────────────────────────

class _SemestreSection extends StatelessWidget {
  final int semestre;
  final List<SiiKardexItem> items;
  const _SemestreSection({required this.semestre, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = items.map((i) => parseGrade(i.calificacion)).toList();
    final avg = averageOf(grades);
    final aprobadas =
        items.where((i) => (parseGrade(i.calificacion) ?? 0) >= 70).length;
    final reprobadas = items.length - aprobadas;
    final creditos = items.fold<double>(
        0, (s, i) => s + (double.tryParse(i.creditos) ?? 0));

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Quita el borde por defecto del ExpansionTile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withAlpha(30),
            child: Text(
              '$semestre',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          title: Text(
            'Semestre $semestre',
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${items.length} materias · ${creditos.toStringAsFixed(0)} créditos',
            style: GoogleFonts.poppins(
                fontSize: 11, color: cs.onSurface.withAlpha(160)),
          ),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: gradeColor(avg, cs: cs).withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              avg == null ? '—' : avg.toStringAsFixed(1),
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gradeColor(avg, cs: cs)),
            ),
          ),
          children: [
            // Mini-barra de proporción aprobadas/reprobadas
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      if (aprobadas > 0)
                        Expanded(
                          flex: aprobadas,
                          child: Container(color: AppColors.green),
                        ),
                      if (reprobadas > 0)
                        Expanded(
                          flex: reprobadas,
                          child: Container(color: AppColors.error),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ...items.map((i) => _KardexRow(item: i)),
          ],
        ),
      ),
    );
  }
}

// ── Fila de una materia del kárdex ──────────────────────────────────────────

class _KardexRow extends StatelessWidget {
  final SiiKardexItem item;
  const _KardexRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grade = parseGrade(item.calificacion);
    final color = gradeColor(grade, cs: cs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombreMateria,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  children: [
                    _MiniTag(text: item.claveMateria),
                    _MiniTag(text: item.periodo),
                    _MiniTag(text: '${item.creditos} créd.'),
                    if (item.descripcion.isNotEmpty)
                      _MiniTag(
                        text: item.descripcion,
                        color: color,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              grade == null ? (item.calificacion.isEmpty ? '—' : item.calificacion)
                  : grade.toStringAsFixed(1),
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color? color;
  const _MiniTag({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface.withAlpha(140);
    return Text(
      text,
      style: GoogleFonts.poppins(
          fontSize: 10.5,
          color: c,
          fontWeight: color != null ? FontWeight.w600 : FontWeight.w400),
    );
  }
}
