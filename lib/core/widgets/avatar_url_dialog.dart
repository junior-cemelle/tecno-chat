import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';

/// Abre el diálogo de foto de perfil.
/// Retorna la URL confirmada, '' si el usuario elige iniciales, null si cancela.
Future<String?> showAvatarUrlDialog(
    BuildContext context, String currentUrl) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _AvatarUrlDialog(initialUrl: currentUrl),
  );
}

class _AvatarUrlDialog extends StatefulWidget {
  final String initialUrl;
  const _AvatarUrlDialog({required this.initialUrl});

  @override
  State<_AvatarUrlDialog> createState() => _AvatarUrlDialogState();
}

class _AvatarUrlDialogState extends State<_AvatarUrlDialog> {
  late final TextEditingController _ctrl;
  String _preview = '';
  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialUrl);
    _preview = widget.initialUrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Subir imagen a Catbox.moe ─────────────────────────────────────────────

  Future<void> _uploadToCatbox() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://catbox.moe/user/api.php'),
      );
      request.fields['reqtype'] = 'fileupload';
      request.files.add(await http.MultipartFile.fromPath(
        'fileToUpload',
        file.path,
      ));

      final streamed = await request.send().timeout(
            const Duration(seconds: 30),
          );
      final body = (await streamed.stream.bytesToString()).trim();

      if (streamed.statusCode == 200 && body.startsWith('http')) {
        if (mounted) {
          _ctrl.text = body;
          setState(() => _preview = body);
        }
      } else {
        if (mounted) setState(() => _uploadError = 'Error al subir imagen');
      }
    } catch (e) {
      if (mounted) setState(() => _uploadError = 'Sin conexión o timeout');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Foto de perfil',
        style: GoogleFonts.poppins(
            color: Colors.white, fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Preview circular ──────────────────────────────────────
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkCardAlt,
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _preview.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _preview,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.green),
                        ),
                      ),
                      errorWidget: (_, _, _) => const Icon(
                          Icons.broken_image,
                          color: AppColors.error,
                          size: 36),
                    )
                  : const Icon(Icons.person, color: Colors.white38, size: 40),
            ),
            const SizedBox(height: 16),

            // ── Botón subir a Catbox ──────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _uploadToCatbox,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload_rounded, size: 18),
                label: Text(
                  _uploading ? 'Subiendo...' : 'Subir imagen desde galería',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              ),
            ),

            if (_uploadError != null) ...[
              const SizedBox(height: 6),
              Text(_uploadError!,
                  style: GoogleFonts.poppins(
                      color: AppColors.error, fontSize: 11)),
            ],

            // ── Divisor ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                const Expanded(
                    child: Divider(color: AppColors.border, thickness: 0.5)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o ingresa una URL',
                      style: GoogleFonts.poppins(
                          color: AppColors.textHint, fontSize: 11)),
                ),
                const Expanded(
                    child: Divider(color: AppColors.border, thickness: 0.5)),
              ]),
            ),

            // ── Campo URL manual ──────────────────────────────────────
            TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://files.catbox.moe/abc.jpg',
                hintStyle:
                    const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: AppColors.darkCardAlt,
                prefixIcon:
                    const Icon(Icons.link, color: Colors.white38, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.green, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _preview = v.trim()),
            ),
            const SizedBox(height: 4),

            // ── Limpiar → usar iniciales ──────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _ctrl.clear();
                  setState(() => _preview = '');
                },
                icon: const Icon(Icons.clear,
                    size: 14, color: AppColors.textHint),
                label: Text(
                  'Usar iniciales (sin foto)',
                  style: GoogleFonts.poppins(
                      color: AppColors.textHint, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar',
              style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Confirmar',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
