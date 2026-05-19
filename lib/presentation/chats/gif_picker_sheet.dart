import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/giphy_service.dart';

Future<GiphyGif?> showGifPicker(BuildContext context) {
  return showModalBottomSheet<GiphyGif>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GifPickerSheet(),
  );
}

class _GifPickerSheet extends StatefulWidget {
  const _GifPickerSheet();

  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> {
  final _giphy = GiphyService();
  final _searchCtrl = TextEditingController();
  List<GiphyGif> _gifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() => _loading = true);
    final gifs =
        query.trim().isEmpty ? await _giphy.trending() : await _giphy.search(query);
    if (mounted) setState(() { _gifs = gifs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(50),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar GIF...',
                  hintStyle: GoogleFonts.poppins(fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _load('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (q) {
                  setState(() {}); // Para mostrar/ocultar sufixIcon
                  if (q.isEmpty) _load('');
                },
                onSubmitted: _load,
              ),
            ),
            // Grid de GIFs
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.green))
                  : _gifs.isEmpty
                      ? Center(
                          child: Text('Sin resultados',
                              style: GoogleFonts.poppins(
                                  color: cs.onSurface.withAlpha(120))))
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: _gifs.length,
                          itemBuilder: (_, i) {
                            final gif = _gifs[i];
                            return GestureDetector(
                              onTap: () => Navigator.pop(context, gif),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: gif.previewUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(
                                    color: cs.surfaceContainerHighest,
                                  ),
                                  errorWidget: (_, _, _) => Container(
                                    color: cs.surfaceContainerHighest,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
