import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// Placeholder temporal para las vistas SII aún no implementadas
/// (calificaciones, kárdex, horarios). Se reemplazará por la pantalla real
/// endpoint por endpoint.
class SiiPlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String descripcion;
  const SiiPlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.descripcion,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: AppColors.green.withAlpha(180)),
              const SizedBox(height: 18),
              Text(
                'Próximamente',
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                descripcion,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: cs.onSurface.withAlpha(170)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
