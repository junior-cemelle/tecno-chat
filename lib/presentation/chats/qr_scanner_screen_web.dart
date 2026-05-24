import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Stub de QR scanner para web — mobile_scanner no soporta web.
class QrScannerScreen extends StatelessWidget {
  const QrScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner,
                size: 72, color: AppColors.primary.withAlpha(120)),
            const SizedBox(height: 20),
            Text(
              'Escáner no disponible en web',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Usa la app móvil para escanear códigos QR.',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(140)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
