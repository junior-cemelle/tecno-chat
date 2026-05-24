import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/platform/download_util.dart';
import '../../core/theme/app_colors.dart';

/// Muestra una imagen (o GIF) en un modal centrado con fondo degradado oscuro.
/// Soporta zoom y pan vía InteractiveViewer + botones de zoom/fit.
Future<void> showImageViewer(BuildContext context, String url,
    {bool isGif = false}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, sec) => _ImageViewer(url: url, isGif: isGif),
    transitionBuilder: (ctx, anim, sec, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _ImageViewer extends StatefulWidget {
  final String url;
  final bool isGif;
  const _ImageViewer({required this.url, required this.isGif});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _transformCtrl = TransformationController();
  static const _minScale = 1.0;
  static const _maxScale = 5.0;
  static const _step = 0.5;

  double get _scale => _transformCtrl.value.getMaxScaleOnAxis();

  void _setScale(double newScale) {
    final clamped = newScale.clamp(_minScale, _maxScale);
    _transformCtrl.value = Matrix4.identity()
      ..scaleByDouble(clamped, clamped, clamped, 1);
    setState(() {});
  }

  void _zoomIn() => _setScale(_scale + _step);
  void _zoomOut() => _setScale(_scale - _step);
  void _fitToScreen() => _setScale(_minScale);

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Para GIFs usamos Image.network para que se animen.
    final Widget image = widget.isGif
        ? Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, prog) {
              if (prog == null) return child;
              return const Center(
                  child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                          color: AppColors.green)));
            },
            errorBuilder: (ctx, err, st) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64),
          )
        : CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.contain,
            placeholder: (ctx, u) => const Center(
                child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                        color: AppColors.green))),
            errorWidget: (ctx, u, err) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64),
          );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ── Fondo con degradado oscuro ───────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Colors.black.withAlpha(180),
                      Colors.black.withAlpha(240),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Imagen centrada con zoom interactivo ────────────────────
          // ClipRect impide que el contenido escalado se desborde fuera del
          // contenedor reservado, evitando el efecto de "crop" sobre el chat
          // de fondo cuando se hace zoom.
          Center(
            child: SizedBox(
              width: size.width * 0.85,
              height: size.height * 0.85,
              child: ClipRect(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: InteractiveViewer(
                    transformationController: _transformCtrl,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    onInteractionEnd: (_) => setState(() {}),
                    child: image,
                  ),
                ),
              ),
            ),
          ),

          // ── Barra superior: cerrar + descargar ───────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _CircleBtn(
                    icon: Icons.arrow_back,
                    tooltip: 'Regresar',
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (canDownload)
                    _CircleBtn(
                      icon: Icons.download_rounded,
                      tooltip: widget.isGif
                          ? 'Descargar GIF'
                          : 'Descargar imagen',
                      onTap: () => downloadFile(widget.url,
                          widget.isGif ? 'image.gif' : 'image.jpg'),
                    ),
                ],
              ),
            ),
          ),

          // ── Controles de zoom abajo ──────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CircleBtn(
                      icon: Icons.zoom_out_rounded,
                      tooltip: 'Alejar',
                      onTap: _scale <= _minScale ? null : _zoomOut,
                    ),
                    const SizedBox(width: 12),
                    _CircleBtn(
                      icon: Icons.fit_screen_rounded,
                      tooltip: 'Ajustar a pantalla',
                      onTap: _scale == _minScale ? null : _fitToScreen,
                    ),
                    const SizedBox(width: 12),
                    _CircleBtn(
                      icon: Icons.zoom_in_rounded,
                      tooltip: 'Acercar',
                      onTap: _scale >= _maxScale ? null : _zoomIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Botón circular reutilizable ───────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _CircleBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withAlpha(disabled ? 60 : 120),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon,
                color: disabled ? Colors.white38 : Colors.white),
          ),
        ),
      ),
    );
  }
}
