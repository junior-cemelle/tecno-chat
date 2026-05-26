import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/sii_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sii_provider.dart';
import 'sii_error_view.dart';

class SiiDashboardScreen extends ConsumerWidget {
  const SiiDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(siiEstudianteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio académico'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(siiEstudianteProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (e, _) => SiiErrorView(
          error: e,
          onRetry: () => ref.invalidate(siiEstudianteProvider),
        ),
        data: (est) => _DashboardBody(estudiante: est),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final SiiEstudiante estudiante;
  const _DashboardBody({required this.estudiante});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () async {
        ref.invalidate(siiEstudianteProvider);
        await ref.read(siiEstudianteProvider.future);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              _HeaderCard(estudiante: estudiante),
              const SizedBox(height: 18),

              // ── Avance + Promedios (lado a lado en wide) ────────────────
              LayoutBuilder(builder: (ctx, c) {
                final wide = c.maxWidth >= 640;
                final avance = _AvanceCard(
                  porcentaje: estudiante.porcentajeAvance,
                  porcentajeCursando: estudiante.porcentajeAvanceCursando,
                );
                final promedios = _PromediosCard(
                  ponderado: estudiante.promedioPonderado,
                  aritmetico: estudiante.promedioAritmetico,
                );
                if (!wide) {
                  return Column(
                    children: [
                      avance,
                      const SizedBox(height: 14),
                      promedios,
                    ],
                  );
                }
                // Sin `crossAxisAlignment: stretch`: el Row vive en un
                // ListView (altura infinita) y stretch propagaría esa
                // altura infinita a los hijos. Cada card ya define su
                // propia altura interna con SizedBox(height: 180).
                return Row(
                  children: [
                    Expanded(child: avance),
                    const SizedBox(width: 14),
                    Expanded(child: promedios),
                  ],
                );
              }),
              const SizedBox(height: 18),

              // ── Distribución de materias (donut) ─────────────────────────
              _MateriasDistribucionCard(estudiante: estudiante),
              const SizedBox(height: 18),

              // ── Créditos + Repeticiones ─────────────────────────────────
              _MetricsGrid(estudiante: estudiante),
              const SizedBox(height: 12),

              Center(
                child: Text(
                  'Datos en vivo desde SII · TecNM Celaya',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(120),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _HeaderCard extends ConsumerWidget {
  final SiiEstudiante estudiante;
  const _HeaderCard({required this.estudiante});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = switch (ref.watch(currentUserProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final avatarUrl = user?.avatarUrl ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white24,
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? const Icon(Icons.person, color: Colors.white, size: 30)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estudiante.persona,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Chip(
                        icon: Icons.badge_outlined,
                        text: 'Nº ${estudiante.numeroControl}'),
                    const SizedBox(width: 6),
                    _Chip(
                        icon: Icons.school_outlined,
                        text: '${estudiante.semestre}° sem'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Avance (ring) ───────────────────────────────────────────────────────────

class _AvanceCard extends StatelessWidget {
  final double porcentaje;
  final double porcentajeCursando;
  const _AvanceCard(
      {required this.porcentaje, required this.porcentajeCursando});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Card(
      title: 'Avance del plan',
      child: SizedBox(
        height: 180,
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: CustomPaint(
                painter: _RingPainter(
                  base: porcentaje / 100,
                  overlay: porcentajeCursando / 100,
                  baseColor: AppColors.green,
                  overlayColor: AppColors.primary.withAlpha(140),
                  track: cs.onSurface.withAlpha(20),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${porcentaje.toStringAsFixed(1)}%',
                        style: GoogleFonts.poppins(
                            fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      Text('acreditado',
                          style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: cs.onSurface.withAlpha(160))),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LegendDot(
                    color: AppColors.green,
                    text:
                        'Acreditado · ${porcentaje.toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 6),
                  _LegendDot(
                    color: AppColors.primary,
                    text:
                        'Cursando · +${porcentajeCursando.toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Si apruebas todo lo del semestre llegarías a '
                    '${(porcentaje + porcentajeCursando).clamp(0, 100).toStringAsFixed(1)}%.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: cs.onSurface.withAlpha(170)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double base;
  final double overlay;
  final Color baseColor;
  final Color overlayColor;
  final Color track;
  _RingPainter({
    required this.base,
    required this.overlay,
    required this.baseColor,
    required this.overlayColor,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 14.0;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.min(size.width, size.height) / 2 - stroke / 2,
    );
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = baseColor;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * base.clamp(0, 1), false,
        basePaint);

    // Overlay parte donde termina la base (avance proyectado por cursando)
    final overlayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = overlayColor;
    final overlaySweep =
        math.pi * 2 * overlay.clamp(0, 1 - base.clamp(0, 1));
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 2 * base.clamp(0, 1),
        overlaySweep, false, overlayPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.base != base ||
      old.overlay != overlay ||
      old.baseColor != baseColor ||
      old.overlayColor != overlayColor;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendDot({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              style: GoogleFonts.poppins(fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Promedios ───────────────────────────────────────────────────────────────

class _PromediosCard extends StatelessWidget {
  final String ponderado;
  final String aritmetico;
  const _PromediosCard({required this.ponderado, required this.aritmetico});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pond = double.tryParse(ponderado) ?? 0;
    final arit = double.tryParse(aritmetico) ?? 0;

    return _Card(
      title: 'Promedios',
      child: SizedBox(
        height: 180,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _PromedioBar(
                label: 'Ponderado',
                value: pond,
                color: AppColors.green),
            _PromedioBar(
                label: 'Aritmético',
                value: arit,
                color: AppColors.primary),
            Text(
              pond >= arit
                  ? 'Las materias con más créditos te están sumando.'
                  : 'Las materias de menor crédito están jalando tu ponderado.',
              style: GoogleFonts.poppins(
                  fontSize: 10.5, color: cs.onSurface.withAlpha(160)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PromedioBar extends StatelessWidget {
  final String label;
  final double value; // 0..100
  final Color color;
  const _PromedioBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.poppins(fontSize: 12)),
            Text(value.toStringAsFixed(2),
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0, 1),
            minHeight: 8,
            backgroundColor: cs.onSurface.withAlpha(20),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ── Materias acreditadas/reprobadas/cursadas ────────────────────────────────

class _MateriasDistribucionCard extends StatelessWidget {
  final SiiEstudiante estudiante;
  const _MateriasDistribucionCard({required this.estudiante});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aprobadas = int.tryParse(estudiante.materiasAprobadas) ?? 0;
    final reprobadas = int.tryParse(estudiante.materiasReprobadas) ?? 0;
    final cursadas = int.tryParse(estudiante.materiasCursadas) ?? 0;
    // "cursadas" del backend = total histórico cursado. Mostramos el desglose.
    final total = math.max(cursadas, aprobadas + reprobadas);

    return _Card(
      title: 'Materias',
      child: Column(
        children: [
          SizedBox(
            height: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
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
                  if (total - aprobadas - reprobadas > 0)
                    Expanded(
                      flex: total - aprobadas - reprobadas,
                      child: Container(color: cs.onSurface.withAlpha(40)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LegendCount(
                  color: AppColors.green,
                  label: 'Aprobadas',
                  count: aprobadas),
              const SizedBox(width: 18),
              _LegendCount(
                  color: AppColors.error,
                  label: 'Reprobadas',
                  count: reprobadas),
              const SizedBox(width: 18),
              _LegendCount(
                  color: cs.onSurface.withAlpha(120),
                  label: 'Cursadas',
                  count: cursadas),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendCount extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _LegendCount(
      {required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: cs.onSurface.withAlpha(170))),
        ]),
        const SizedBox(height: 2),
        Text('$count',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Métricas adicionales ────────────────────────────────────────────────────

class _MetricsGrid extends StatelessWidget {
  final SiiEstudiante estudiante;
  const _MetricsGrid({required this.estudiante});

  @override
  Widget build(BuildContext context) {
    final items = <_Metric>[
      _Metric(
          icon: Icons.workspace_premium_outlined,
          label: 'Créditos acumulados',
          value: estudiante.creditosAcumulados,
          color: AppColors.primary),
      _Metric(
          icon: Icons.add_chart_outlined,
          label: 'Créditos complementarios',
          value: '${estudiante.creditosComplementarios}',
          color: AppColors.greenDark),
      _Metric(
          icon: Icons.warning_amber_rounded,
          label: 'No acreditadas',
          value: estudiante.numMatRepNoAcreditadas,
          color: AppColors.error),
      _Metric(
          icon: Icons.replay_circle_filled_outlined,
          label: 'Rep. 1ª oportunidad',
          value: estudiante.numMateriasRepPrimera ?? '0',
          color: Colors.orange),
      _Metric(
          icon: Icons.refresh_rounded,
          label: 'Rep. 2ª oportunidad',
          value: estudiante.numMateriasRepSegunda ?? '0',
          color: Colors.deepOrange),
    ];

    return LayoutBuilder(builder: (ctx, c) {
      final cols = (c.maxWidth / 200).floor().clamp(2, 4);
      final spacing = 12.0;
      final itemW = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: items
            .map((m) => SizedBox(width: itemW, child: _MetricTile(metric: m)))
            .toList(),
      );
    });
  }
}

class _Metric {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Metric(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});
}

class _MetricTile extends StatelessWidget {
  final _Metric metric;
  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: metric.color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(metric.icon, color: metric.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: cs.onSurface.withAlpha(170))),
                const SizedBox(height: 2),
                Text(metric.value,
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card base ───────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withAlpha(180))),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
