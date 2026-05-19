import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_assets.dart';

/// Fondo con crossfade real entre imágenes usando AnimatedSwitcher.
class FadeBackground extends StatefulWidget {
  const FadeBackground({super.key});

  @override
  State<FadeBackground> createState() => _FadeBackgroundState();
}

class _FadeBackgroundState extends State<FadeBackground> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) {
        setState(() =>
            _index = (_index + 1) % AppAssets.bgLogin.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1400),
      // Imagen nueva entra encima con fade-in mientras la vieja permanece
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          ...previous,
          if (current != null) current,
        ],
      ),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _BgImage(key: ValueKey(_index), path: AppAssets.bgLogin[_index]),
    );
  }
}

class _BgImage extends StatelessWidget {
  final String path;
  const _BgImage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
  }
}
