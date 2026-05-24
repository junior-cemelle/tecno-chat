import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../core/platform/download_util.dart';
import '../../core/theme/app_colors.dart';

/// Muestra el video en un modal centrado sobre la página actual.
/// Fondo con degradado oscuro, click fuera del video lo cierra.
Future<void> showVideoViewer(BuildContext context, String url) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, sec) => _VideoViewer(url: url),
    transitionBuilder: (ctx, anim, sec, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _VideoViewer extends StatefulWidget {
  final String url;
  const _VideoViewer({required this.url});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.setLooping(true); // reproducción en bucle
    _controller.addListener(_onControllerUpdate);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final isPlaying = _controller.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    _controller.value.isPlaying ? _controller.pause() : _controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ── Fondo con degradado oscuro (click cierra el modal) ────────
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

          // ── Video centrado ───────────────────────────────────────────
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width * 0.72,
                maxHeight: size.height * 0.78,
              ),
              child: _error
                  ? _ErrorView(onClose: () => Navigator.pop(context))
                  : !_initialized
                      ? const SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                              color: AppColors.green))
                      : AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _togglePlay,
                            child: Stack(
                              children: [
                                VideoPlayer(_controller),
                                // Overlay con icono cuando está pausado
                                if (!_isPlaying)
                                  Center(
                                    child: Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            Colors.black.withAlpha(120),
                                      ),
                                      child: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 64,
                                          color: Colors.white),
                                    ),
                                  ),
                                // Barra de control inferior
                                Positioned(
                                  left: 0, right: 0, bottom: 0,
                                  child: _BottomControls(
                                    controller: _controller,
                                    isPlaying: _isPlaying,
                                    onTogglePlay: _togglePlay,
                                  ),
                                ),
                              ],
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
                      tooltip: 'Descargar video',
                      onTap: () => downloadFile(widget.url, 'video.mp4'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Barra de controles inferior (play/pause + progress) ───────────────────────

class _BottomControls extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isPlaying;
  final VoidCallback onTogglePlay;

  const _BottomControls({
    required this.controller,
    required this.isPlaying,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withAlpha(200),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botón play/pause + indicador loop
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                tooltip: isPlaying ? 'Pausar' : 'Reproducir',
                onPressed: onTogglePlay,
              ),
              const Icon(Icons.loop_rounded,
                  color: Colors.white54, size: 16),
              const SizedBox(width: 4),
              const Text('En bucle',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const Spacer(),
              _PositionText(controller: controller),
            ],
          ),
          // Barra de progreso scrubeable
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: EdgeInsets.zero,
            colors: const VideoProgressColors(
              playedColor: AppColors.green,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionText extends StatefulWidget {
  final VideoPlayerController controller;
  const _PositionText({required this.controller});

  @override
  State<_PositionText> createState() => _PositionTextState();
}

class _PositionTextState extends State<_PositionText> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.controller.value;
    return Text(
      '${_fmt(v.position)} / ${_fmt(v.duration)}',
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}

// ── Botón circular reutilizable ───────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _CircleBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withAlpha(120),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ── Vista de error ────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onClose;
  const _ErrorView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white70, size: 56),
        const SizedBox(height: 12),
        Text('No se pudo cargar el video',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 12),
        TextButton(
            onPressed: onClose,
            child: Text('Cerrar',
                style: GoogleFonts.poppins(color: AppColors.green))),
      ],
    );
  }
}
