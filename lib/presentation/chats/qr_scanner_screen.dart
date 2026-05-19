import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/qr_dialog.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    final uid = decodeQr(raw);
    if (uid == null) return;

    setState(() => _processing = true);
    await _controller.stop();

    final contact = await ref
        .read(firestoreServiceProvider)
        .findUserByUid(uid);

    if (!mounted) return;

    if (contact == null) {
      _snack('Usuario no encontrado');
      setState(() => _processing = false);
      await _controller.start();
      return;
    }

    final me = await ref.read(currentUserProvider.future);
    if (me == null) return;

    if (contact.uid == me.uid) {
      _snack('No puedes agregarte a ti mismo');
      setState(() => _processing = false);
      await _controller.start();
      return;
    }

    if (!mounted) return;

    final confirmed = await _showConfirm(contact);
    if (confirmed == true && mounted) {
      await ref
          .read(firestoreServiceProvider)
          .addContact(me.uid, contact.uid);
      ref.invalidate(contactsProvider);
      ref.invalidate(currentUserProvider);

      if (mounted) {
        Navigator.pop(context, contact); // retorna el contacto seleccionado
      }
    } else {
      setState(() => _processing = false);
      await _controller.start();
    }
  }

  Future<bool?> _showConfirm(UserModel contact) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      // dialogContext es el contexto del dialog — usar este para pop
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cs.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Agregar contacto',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primary,
              backgroundImage: contact.avatarUrl.isNotEmpty
                  ? NetworkImage(contact.avatarUrl)
                  : null,
              child: contact.avatarUrl.isEmpty
                  ? Text(
                      contact.displayName.isNotEmpty
                          ? contact.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(contact.displayName,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            Text(contact.email,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: cs.onSurface.withAlpha(160))),
            const SizedBox(height: 4),
            Text(contact.isTeacher ? 'Profesor' : 'Alumno',
                style: TextStyle(
                    color: contact.isTeacher
                        ? AppColors.primary
                        : AppColors.greenDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text('Agregar',
                  style: GoogleFonts.poppins(color: Colors.white))),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Marco de escaneo
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.green, width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Instrucción
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text(
              'Apunta al código QR del contacto',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 14),
            ),
          ),
          if (_processing)
            const Center(child: CircularProgressIndicator(color: AppColors.green)),
        ],
      ),
    ),   // Scaffold
    );   // PopScope
  }
}
