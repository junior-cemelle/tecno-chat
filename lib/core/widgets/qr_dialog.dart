import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../../data/models/user_model.dart';

/// Prefijo embebido en el QR para identificar la app.
const _qrPrefix = 'techat://';

String encodeQr(String uid) => '$_qrPrefix$uid';

/// Decodifica el UID desde el QR. Retorna null si el formato no coincide.
String? decodeQr(String raw) {
  if (raw.startsWith(_qrPrefix)) return raw.substring(_qrPrefix.length);
  // Compatibilidad: si es solo un UID sin prefijo
  if (raw.length > 10 && !raw.contains(' ')) return raw;
  return null;
}

/// Muestra el diálogo con el QR del usuario.
Future<void> showMyQrDialog(BuildContext context, UserModel user) {
  return showDialog(
    context: context,
    builder: (_) => _QrDialog(user: user),
  );
}

class _QrDialog extends StatelessWidget {
  final UserModel user;
  const _QrDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qrData = encodeQr(user.uid);

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mi código QR',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pide a otro usuario que lo escanee\npara agregarte como contacto',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12, color: cs.onSurface.withAlpha(160)),
          ),
          const SizedBox(height: 20),
          // ── QR ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 220,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── Info del usuario ─────────────────────────────────────────
          Text(
            user.displayName,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          if (user.email.isNotEmpty)
            Text(
              user.email,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: cs.onSurface.withAlpha(160)),
            ),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: user.isTeacher
                  ? AppColors.primary.withAlpha(30)
                  : AppColors.green.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              user.isTeacher ? 'Profesor' : 'Alumno',
              style: TextStyle(
                color: user.isTeacher
                    ? AppColors.primary
                    : AppColors.greenDark,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cerrar',
              style: GoogleFonts.poppins(color: cs.primary)),
        ),
      ],
    );
  }
}
