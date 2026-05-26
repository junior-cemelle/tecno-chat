import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/sii_models.dart';
import '../../providers/sii_provider.dart';
import 'sii_error_view.dart';

/// `GET /api/movil/estudiante/horarios` — agrupado por periodo.
///
/// UX: selector horizontal de periodos + grid semanal (días × horas) con
/// bloques de clase posicionados absolutamente por su hora de inicio/fin.
/// Cada clase ocupa una sola columna por día — si una materia da clase
/// lunes y miércoles aparece como dos bloques.
class SiiHorariosScreen extends ConsumerStatefulWidget {
  const SiiHorariosScreen({super.key});

  @override
  ConsumerState<SiiHorariosScreen> createState() =>
      _SiiHorariosScreenState();
}

class _SiiHorariosScreenState extends ConsumerState<SiiHorariosScreen> {
  String? _selectedClave;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(siiHorariosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horarios'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(siiHorariosProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (e, _) => SiiErrorView(
          error: e,
          onRetry: () => ref.invalidate(siiHorariosProvider),
        ),
        data: (periodos) {
          if (periodos.isEmpty) {
            return _empty(
              icon: Icons.event_busy_outlined,
              title: 'Sin horarios cargados',
              subtitle:
                  'No tienes clases asignadas en ningún periodo todavía.',
            );
          }
          final exists =
              periodos.any((p) => p.periodo.clavePeriodo == _selectedClave);
          final selectedClave =
              exists ? _selectedClave! : periodos.last.periodo.clavePeriodo;
          final selected = periodos
              .firstWhere((p) => p.periodo.clavePeriodo == selectedClave);

          return _Body(
            periodos: periodos,
            selected: selected,
            onSelectPeriodo: (c) => setState(() => _selectedClave = c),
          );
        },
      ),
    );
  }

  Widget _empty(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.onSurface.withAlpha(110)),
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

class _Body extends StatelessWidget {
  final List<SiiPeriodoHorario> periodos;
  final SiiPeriodoHorario selected;
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
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PeriodoSelector(
              periodos: periodos,
              selectedClave: selected.periodo.clavePeriodo,
              onSelect: onSelectPeriodo,
            ),
            Expanded(
              child: selected.horario.isEmpty
                  ? Center(
                      child: Text(
                        'Sin clases en este periodo.',
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                    )
                  : _WeekGrid(items: selected.horario),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selector de periodo ──────────────────────────────────────────────────────

class _PeriodoSelector extends StatelessWidget {
  final List<SiiPeriodoHorario> periodos;
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

// ── Grid semanal ────────────────────────────────────────────────────────────

/// Bloque de clase ya resuelto (día + horario parseado) listo para posicionar.
class _Slot {
  final int dayIndex; // 0=Lun ... 5=Sab
  final double startHour; // 7.0 = 07:00, 7.5 = 07:30
  final double endHour;
  final String materia;
  final String claveMateria;
  final String grupo;
  final String? salon;
  final Color color;

  const _Slot({
    required this.dayIndex,
    required this.startHour,
    required this.endHour,
    required this.materia,
    required this.claveMateria,
    required this.grupo,
    required this.salon,
    required this.color,
  });
}

class _WeekGrid extends StatelessWidget {
  static const _days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

  // Paleta cíclica — cada materia (idGrupo) recibe un color estable.
  static const _palette = [
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFE64A19),
    Color(0xFF7B1FA2),
    Color(0xFF00897B),
    Color(0xFFC2185B),
    Color(0xFF5D4037),
    Color(0xFF455A64),
    Color(0xFFFFA000),
    Color(0xFF512DA8),
  ];

  final List<SiiHorarioItem> items;
  const _WeekGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    // 1) Asignar color por materia (mismo grupo = mismo color)
    final colorByGrupo = <int, Color>{};
    for (var i = 0; i < items.length; i++) {
      colorByGrupo[items[i].idGrupo] = _palette[i % _palette.length];
    }

    // 2) Expandir cada item a slots (uno por día con clase)
    final slots = <_Slot>[];
    for (final it in items) {
      final color = colorByGrupo[it.idGrupo]!;
      _addSlot(slots, 0, it.lunes, it.lunesClaveSalon, it, color);
      _addSlot(slots, 1, it.martes, it.martesClaveSalon, it, color);
      _addSlot(slots, 2, it.miercoles, it.miercolesClaveSalon, it, color);
      _addSlot(slots, 3, it.jueves, it.juevesClaveSalon, it, color);
      _addSlot(slots, 4, it.viernes, it.viernesClaveSalon, it, color);
      _addSlot(slots, 5, it.sabado, it.sabadoClaveSalon, it, color);
    }

    if (slots.isEmpty) {
      return Center(
        child: Text(
          'Las clases no tienen horarios parseables.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
      );
    }

    // 3) Calcular rango de horas (con padding para visual breathing room)
    final minHour =
        slots.map((s) => s.startHour).reduce((a, b) => a < b ? a : b).floor();
    final maxHour =
        slots.map((s) => s.endHour).reduce((a, b) => a > b ? a : b).ceil();
    final hoursRange = maxHour - minHour;

    const double hourHeight = 64; // px por hora
    const double timeColWidth = 50;
    const double headerHeight = 36;

    return LayoutBuilder(builder: (ctx, c) {
      // En móvil necesitamos scroll horizontal — el grid completo requiere
      // al menos timeColWidth + 6 * 80px = 530px. Si la pantalla es más
      // angosta, se desplaza horizontalmente.
      const double minDayColWidth = 90;
      final availableForDays = c.maxWidth - timeColWidth;
      final dayColWidth =
          (availableForDays / 6).clamp(minDayColWidth, 220.0);
      final gridWidth = timeColWidth + dayColWidth * 6;

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header con días
              SizedBox(
                height: headerHeight,
                child: Row(
                  children: [
                    SizedBox(width: timeColWidth),
                    for (final d in _days)
                      Expanded(
                        child: Center(
                          child: Text(d,
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
              // Grid scrolleable verticalmente
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.only(bottom: 24),
                  child: SizedBox(
                    height: hoursRange * hourHeight,
                    child: Stack(
                      children: [
                        _GridBackground(
                          minHour: minHour,
                          maxHour: maxHour,
                          hourHeight: hourHeight,
                          timeColWidth: timeColWidth,
                          dayColWidth: dayColWidth,
                        ),
                        for (final s in slots)
                          Positioned(
                            top: (s.startHour - minHour) * hourHeight,
                            left: timeColWidth + s.dayIndex * dayColWidth,
                            width: dayColWidth,
                            height: (s.endHour - s.startHour) * hourHeight,
                            child: _ClassBlock(slot: s),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _addSlot(List<_Slot> out, int day, String? range, String? salon,
      SiiHorarioItem it, Color color) {
    final parsed = _parseRange(range);
    if (parsed == null) return;
    out.add(_Slot(
      dayIndex: day,
      startHour: parsed.$1,
      endHour: parsed.$2,
      materia: it.nombreMateria,
      claveMateria: it.claveMateria,
      grupo: it.letraGrupo,
      salon: salon,
      color: color,
    ));
  }

  /// Parsea "HH:MM-HH:MM" → (startInHours, endInHours). Null si no aplica.
  static (double, double)? _parseRange(String? range) {
    if (range == null || range.isEmpty) return null;
    final parts = range.split('-');
    if (parts.length != 2) return null;
    final start = _hhmmToDouble(parts[0].trim());
    final end = _hhmmToDouble(parts[1].trim());
    if (start == null || end == null || end <= start) return null;
    return (start, end);
  }

  static double? _hhmmToDouble(String s) {
    final p = s.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h + m / 60.0;
  }
}

// Fondo del grid: líneas horarias horizontales + columnas verticales + labels.
class _GridBackground extends StatelessWidget {
  final int minHour;
  final int maxHour;
  final double hourHeight;
  final double timeColWidth;
  final double dayColWidth;

  const _GridBackground({
    required this.minHour,
    required this.maxHour,
    required this.hourHeight,
    required this.timeColWidth,
    required this.dayColWidth,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lineColor = cs.onSurface.withAlpha(20);

    return Stack(
      children: [
        // Filas: una línea por hora + label de la hora
        for (int h = minHour; h <= maxHour; h++)
          Positioned(
            top: (h - minHour) * hourHeight,
            left: 0,
            right: 0,
            child: Row(
              children: [
                SizedBox(
                  width: timeColWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${h.toString().padLeft(2, '0')}:00',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: cs.onSurface.withAlpha(140)),
                    ),
                  ),
                ),
                Expanded(child: Container(height: 1, color: lineColor)),
              ],
            ),
          ),
        // Columnas verticales (divisores entre días)
        for (int d = 0; d <= 6; d++)
          Positioned(
            top: 0,
            bottom: 0,
            left: timeColWidth + d * dayColWidth,
            child: Container(width: 1, color: lineColor),
          ),
      ],
    );
  }
}

// Bloque visual de una clase.
class _ClassBlock extends StatelessWidget {
  final _Slot slot;
  const _ClassBlock({required this.slot});

  @override
  Widget build(BuildContext context) {
    final duration = slot.endHour - slot.startHour;
    final compact = duration < 1.25; // menos de 1h15: ocultar metadatos
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message:
            '${slot.materia}\n${slot.claveMateria} · Grupo ${slot.grupo}'
            '${slot.salon != null ? "\nSalón ${slot.salon}" : ""}\n'
            '${_fmt(slot.startHour)} - ${_fmt(slot.endHour)}',
        child: Material(
          color: slot.color.withAlpha(220),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.materia,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${slot.claveMateria} · ${slot.grupo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          color: Colors.white.withAlpha(220)),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (slot.salon != null) ...[
                          const Icon(Icons.room_outlined,
                              size: 11, color: Colors.white70),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              slot.salon!,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  color: Colors.white.withAlpha(220)),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${_fmt(slot.startHour)}-${_fmt(slot.endHour)}',
                          style: GoogleFonts.poppins(
                              fontSize: 9,
                              color: Colors.white.withAlpha(200)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double h) {
    final hh = h.floor();
    final mm = ((h - hh) * 60).round();
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }
}
