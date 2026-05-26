import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../data/services/asesoria_service.dart';
import '../../providers/asesoria_provider.dart';
import '../../providers/auth_provider.dart';

/// Form para que un alumno solicite ser asesor: materia + motivos + CV PDF.
/// La validación dura (rol alumno, semestre ≥4, no duplicar materia) se hace
/// en `AsesoriaService.applyAsAdvisor`; aquí solo damos feedback inmediato
/// al usuario.
class ApplyAdvisorScreen extends ConsumerStatefulWidget {
  const ApplyAdvisorScreen({super.key});

  @override
  ConsumerState<ApplyAdvisorScreen> createState() =>
      _ApplyAdvisorScreenState();
}

class _ApplyAdvisorScreenState extends ConsumerState<ApplyAdvisorScreen> {
  final _materiaCtrl = TextEditingController();
  final _motivosCtrl = TextEditingController();
  Uint8List? _cvBytes;
  String? _cvName;
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _materiaCtrl.dispose();
    _motivosCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // necesitamos los bytes para subir
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      setState(() => _errorMsg = 'No se pudieron leer los bytes del PDF.');
      return;
    }
    // Límite suave en cliente: 5 MB
    if (file.bytes!.length > 5 * 1024 * 1024) {
      setState(() => _errorMsg =
          'El PDF excede 5 MB. Comprime el archivo o adjunta una versión más ligera.');
      return;
    }
    setState(() {
      _cvBytes = file.bytes!;
      _cvName = file.name;
      _errorMsg = null;
    });
  }

  Future<void> _submit(UserModel user) async {
    if (_busy) return;
    final materia = _materiaCtrl.text.trim();
    final motivos = _motivosCtrl.text.trim();
    if (materia.isEmpty || motivos.isEmpty) {
      setState(() => _errorMsg = 'Completa materia y motivos.');
      return;
    }
    if (_cvBytes == null) {
      setState(() => _errorMsg = 'Adjunta tu CV en PDF.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(asesoriaServiceProvider).applyAsAdvisor(
            advisor: user,
            materia: materia,
            motivos: motivos,
            cvBytes: _cvBytes!,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            'Solicitud enviada. El gerente la revisará pronto.'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      context.pop();
    } on AsesoriaException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = 'Error inesperado: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar ser asesor')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, _) =>
            const Center(child: Text('Error cargando perfil')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Sin perfil'));
          }
          // Pre-check para guiar al alumno (la validación final está en el
          // service; esto es solo UX).
          if (!user.isStudent) {
            return _eligibilityNotice(
              cs,
              icon: Icons.block_outlined,
              text:
                  'Solo los alumnos pueden registrarse como asesores.',
            );
          }
          final sem = user.semester ?? 0;
          if (sem < 4) {
            return _eligibilityNotice(
              cs,
              icon: Icons.event_busy_outlined,
              text:
                  'Necesitas cursar al menos 4º semestre para ser asesor. '
                  'Tu semestre actual: $sem.',
            );
          }
          return _form(user);
        },
      ),
    );
  }

  Widget _eligibilityNotice(ColorScheme cs,
      {required IconData icon, required String text}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.onSurface.withAlpha(120)),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: cs.onSurface.withAlpha(180))),
          ],
        ),
      ),
    );
  }

  Widget _form(UserModel user) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.green.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.green.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_outlined,
                      color: AppColors.green, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Como asesor de ${user.semester}º semestre podrás impartir '
                      'una asesoría por materia. El gerente revisará tu '
                      'solicitud y definirá la capacidad de alumnos.',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('Materia',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _materiaCtrl,
              decoration: const InputDecoration(
                hintText: 'Ej: Cálculo Integral, Programación I…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Text('Motivos',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _motivosCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText:
                    'Explica brevemente tu experiencia y por qué quieres asesorar esta materia.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Curriculum (PDF)',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _busy ? null : _pickCv,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _cvBytes != null
                        ? AppColors.green
                        : cs.onSurface.withAlpha(60),
                    width: _cvBytes != null ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _cvBytes != null
                          ? Icons.picture_as_pdf_rounded
                          : Icons.upload_file_outlined,
                      color: _cvBytes != null
                          ? AppColors.error
                          : cs.onSurface.withAlpha(140),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _cvBytes != null
                                ? (_cvName ?? 'cv.pdf')
                                : 'Selecciona tu CV (PDF, máx. 5 MB)',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: _cvBytes != null
                                    ? FontWeight.w600
                                    : FontWeight.w400),
                          ),
                          if (_cvBytes != null)
                            Text(
                              '${(_cvBytes!.length / 1024).toStringAsFixed(1)} KB',
                              style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  color: cs.onSurface.withAlpha(160)),
                            ),
                        ],
                      ),
                    ),
                    if (_cvBytes != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Quitar',
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _cvBytes = null;
                                  _cvName = null;
                                }),
                      ),
                  ],
                ),
              ),
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Text(_errorMsg!,
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: AppColors.error)),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar solicitud'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _busy ? null : () => _submit(user),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const Center(
                child: CircularProgressIndicator(color: AppColors.green),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
