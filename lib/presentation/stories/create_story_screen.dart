import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';
import '../../providers/story_provider.dart';

class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final _textCtrl = TextEditingController();
  XFile? _image;
  bool _publishing = false;
  final Set<String> _selectedGroupIds = {};
  final _picker = ImagePicker();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1080);
    if (xfile != null) setState(() => _image = xfile);
  }

  Future<void> _publish() async {
    if (_textCtrl.text.trim().isEmpty && _image == null) {
      _snack('Escribe un aviso o selecciona una imagen');
      return;
    }
    if (_selectedGroupIds.isEmpty) {
      _snack('Selecciona al menos un grupo');
      return;
    }
    final me = switch (ref.read(currentUserProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (me == null) return;

    setState(() => _publishing = true);
    try {
      String? imageUrl;
      String type = 'text';
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();

      if (_image != null) {
        imageUrl = await StorageService().uploadStoryImage(tempId, _image!);
        type = 'image';
      }

      await ref.read(storyServiceProvider).createStory(
            authorUid: me.uid,
            content: _textCtrl.text.trim(),
            groupIds: _selectedGroupIds.toList(),
            imageUrl: imageUrl,
            type: type,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aviso publicado — expira en 24h'),
          backgroundColor: AppColors.green,
        ));
        context.pop();
      }
    } catch (e) {
      if (mounted) _snack('Error al publicar: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groupsAsync = ref.watch(groupsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Nuevo aviso institucional',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : Text('Publicar',
                    style: GoogleFonts.poppins(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Vista previa ────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  // Fondo degradado siempre visible
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0D1F35), Color(0xFF1A3A5C)],
                      ),
                    ),
                  ),
                  // Imagen seleccionada usando bytes (web + móvil)
                  if (_image != null)
                    FutureBuilder<Uint8List>(
                      future: _image!.readAsBytes(),
                      builder: (_, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        return Image.memory(snap.data!,
                            fit: BoxFit.cover, width: double.infinity);
                      },
                    ),
                  // Overlay oscuro sobre la imagen
                  if (_image != null)
                    Container(color: Colors.black.withAlpha(100)),
                  // Texto de vista previa
                  if (_textCtrl.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _textCtrl.text,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Text('Vista previa del aviso',
                        style: GoogleFonts.poppins(
                            color: Colors.white.withAlpha(120),
                            fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Texto ─────────────────────────────────────────────────────
          TextField(
            controller: _textCtrl,
            maxLines: 4,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: 'Texto del aviso',
              hintText: 'Ej. Examen parcial el viernes a las 10am...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),

          // ── Imagen opcional ───────────────────────────────────────────
          OutlinedButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: Text(
                _image == null ? 'Agregar imagen (opcional)' : 'Cambiar imagen',
                style: GoogleFonts.poppins(fontSize: 13)),
            onPressed: _pickImage,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                label: Text('Quitar imagen',
                    style: GoogleFonts.poppins(
                        color: AppColors.error, fontSize: 12)),
                onPressed: () => setState(() => _image = null),
              ),
            ),
          const SizedBox(height: 16),

          // ── Grupos ────────────────────────────────────────────────────
          _SectionLabel('PUBLICAR EN GRUPOS *'),
          const SizedBox(height: 6),
          groupsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.green)),
            error: (_, _) => const Text('Error al cargar grupos'),
            data: (groups) {
              if (groups.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'No tienes grupos creados.\n'
                    'Crea un grupo primero desde la pestaña Grupos.',
                    style: GoogleFonts.poppins(
                        color: cs.onSurface.withAlpha(140), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Column(
                children: groups
                    .map((g) => CheckboxListTile(
                          value: _selectedGroupIds.contains(g.id),
                          activeColor: AppColors.primary,
                          title: Text(g.groupName ?? 'Grupo',
                              style: GoogleFonts.poppins(fontSize: 14)),
                          subtitle: Text(
                              '${g.participantIds.length} miembros',
                              style: GoogleFonts.poppins(fontSize: 11)),
                          onChanged: (v) => setState(() => v == true
                              ? _selectedGroupIds.add(g.id)
                              : _selectedGroupIds.remove(g.id)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'El aviso expira automáticamente en 24 horas.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8));
}
