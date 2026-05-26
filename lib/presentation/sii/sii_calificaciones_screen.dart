import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/sii_models.dart';
import '../../providers/sii_provider.dart';
import 'sii_error_view.dart';
import 'sii_grade_colors.dart';

/// `GET /api/movil/estudiante/calificaciones` — agrupado por periodo.
///
/// UX: selector horizontal de periodos en la cabecera + lista de materias del
/// periodo seleccionado, cada una con sus parciales como chips de color y un
/// promedio calculado al vuelo. Por defecto se muestra el periodo más reciente
/// (último elemento de la lista del backend).
class SiiCalificacionesScreen extends ConsumerStatefulWidget {
  const SiiCalificacionesScreen({super.key});

  @override
  ConsumerState<SiiCalificacionesScreen> createState() =>
      _SiiCalificacionesScreenState();
}

class _SiiCalificacionesScreenState
    extends ConsumerState<SiiCalificacionesScreen> {
  /// Clave del periodo seleccionado. Si es null se selecciona el último al
  /// recibir datos.
  String? _selectedClave;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(siiCalificacionesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calificaciones'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(siiCalificacionesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (e, _) => SiiErrorView(
          error: e,
          onRetry: () => ref.invalidate(siiCalificacionesProvider),
        ),
        data: (periodos) {
          if (periodos.isEmpty) {
            return _EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Sin periodos cargados',
              subtitle:
                  'Aún no apareces inscrito en ningún periodo con materias.',
            );
          }
          // Si todavía no hay selección o la previa ya no existe, escogemos
          // el último periodo de la lista (suele ser el actual).
          final exists = periodos
              .any((p) => p.periodo.clavePeriodo == _selectedClave);
          final selectedClave =
              exists ? _selectedClave! : periodos.last.periodo.clavePeriodo;
          final selected =
              periodos.firstWhere((p) => p.periodo.clavePeriodo == selectedClave);

          return _Body(
            periodos: periodos,
            selected: selected,
            onSelectPeriodo: (clave) =>
                setState(() => _selectedClave = clave),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<SiiPeriodoCalificaciones> periodos;
  final SiiPeriodoCalificaciones selected;
  final ValueChanged<String> onSelectPeriodo;

  const _Body({
    required this.periodos,
    required this.selected,
    required this.onSelectPeriodo,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PeriodoSelector(
              periodos: periodos,
              selectedClave: selected.periodo.clavePeriodo,
              onSelect: onSelectPeriodo,
            ),
            Expanded(
              child: selected.materias.isEmpty
                  ? _EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Sin materias en este periodo',
                      subtitle:
                          'El periodo no tiene materias registradas todavía.',
                    )
                  : _MateriasList(materias: selected.materias),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selector de periodo (chips horizontales scrolleables) ───────────────────

class _PeriodoSelector extends StatelessWidget {
  final List<SiiPeriodoCalificaciones> periodos;
  final String selectedClave;
  final ValueChanged<String> onSelect;

  const _PeriodoSelector({
    required this.periodos,
    required this.selectedClave,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: periodos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = periodos[i].periodo;
          final isSelected = p.clavePeriodo == selectedClave;
          return ChoiceChip(
            label: Text('${p.descripcionPeriodo} ${p.anio}'),
            selected: isSelected,
            onSelected: (_) => onSelect(p.clavePeriodo),
            selectedColor: AppColors.green.withAlpha(60),
            labelStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? AppColors.greenDark : null,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? AppColors.green
                    : Theme.of(context).dividerColor,
                width: isSelected ? 1.2 : 0.5,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Lista de materias ───────────────────────────────────────────────────────

class _MateriasList extends StatelessWidget {
  final List<SiiMateria> materias;
  const _MateriasList({required this.materias});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Estadística del periodo (promedio agregado de todas las materias).
    final allGrades = materias
        .expand((m) => m.calificaciones.map((c) => parseGrade(c.calificacion)))
        .toList();
    final periodAvg = averageOf(allGrades);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: materias.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == 0) {
          return _PeriodoStatsBar(
            materias: materias,
            promedio: periodAvg,
          );
        }
        final m = materias[i - 1];
        return _MateriaCard(materia: m, surface: cs.surface);
      },
    );
  }
}

class _PeriodoStatsBar extends StatelessWidget {
  final List<SiiMateria> materias;
  final double? promedio;
  const _PeriodoStatsBar({required this.materias, required this.promedio});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalParciales =
        materias.fold<int>(0, (sum, m) => sum + m.calificaciones.length);
    final reportados = materias
        .expand((m) => m.calificaciones)
        .where((c) => parseGrade(c.calificacion) != null)
        .length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: Row(
        children: [
          _Stat(
            label: 'Materias',
            value: '${materias.length}',
            icon: Icons.menu_book_outlined,
            color: AppColors.primary,
          ),
          _StatDivider(),
          _Stat(
            label: 'Parciales',
            value: '$reportados/$totalParciales',
            icon: Icons.checklist_rounded,
            color: AppColors.green,
          ),
          _StatDivider(),
          _Stat(
            label: 'Promedio',
            value: promedio == null
                ? '—'
                : promedio!.toStringAsFixed(1),
            icon: Icons.show_chart_rounded,
            color: gradeColor(promedio, cs: cs),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).dividerColor,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: cs.onSurface.withAlpha(160))),
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card de una materia ─────────────────────────────────────────────────────

class _MateriaCard extends StatelessWidget {
  final SiiMateria materia;
  final Color surface;
  const _MateriaCard({required this.materia, required this.surface});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = materia.calificaciones
        .map((c) => parseGrade(c.calificacion))
        .toList();
    final avg = averageOf(grades);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      materia.nombreMateria,
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${materia.claveMateria} · Grupo ${materia.letraGrupo}',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: cs.onSurface.withAlpha(150)),
                    ),
                  ],
                ),
              ),
              // Promedio de la materia
              Container(
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
            ],
          ),
          const SizedBox(height: 12),
          // Chips de parciales
          if (materia.calificaciones.isEmpty)
            Text(
              'Sin parciales registrados',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: cs.onSurface.withAlpha(140)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in materia.calificaciones)
                  _ParcialChip(
                    numero: c.numeroCalificacion,
                    grade: parseGrade(c.calificacion),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ParcialChip extends StatelessWidget {
  final int numero;
  final double? grade;
  const _ParcialChip({required this.numero, required this.grade});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = gradeColor(grade, cs: cs);
    final hasGrade = grade != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(hasGrade ? 25 : 10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(hasGrade ? 90 : 40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('P$numero',
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withAlpha(160))),
          const SizedBox(width: 6),
          Text(hasGrade ? grade!.toStringAsFixed(1) : '—',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: cs.onSurface.withAlpha(110)),
            const SizedBox(height: 12),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: cs.onSurface.withAlpha(160))),
          ],
        ),
      ),
    );
  }
}
