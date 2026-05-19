import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/story_model.dart';
import '../../providers/firestore_provider.dart';
import '../../providers/story_provider.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryModel> stories;
  final String myUid;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    required this.myUid,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _index;
  late AnimationController _progress;
  Timer? _timer;

  static const _duration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _progress = AnimationController(vsync: this, duration: _duration);
    _startStory();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _startStory() {
    _progress.forward(from: 0);
    _markViewed();
    _timer?.cancel();
    _timer = Timer(_duration, _next);
  }

  void _markViewed() {
    final story = widget.stories[_index];
    if (!story.isViewedBy(widget.myUid) &&
        story.authorUid != widget.myUid) {
      ref
          .read(storyServiceProvider)
          .markAsViewed(story.id, widget.myUid);
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.stories.length) {
      Navigator.pop(context);
      return;
    }
    setState(() => _index = index);
    _startStory();
  }

  void _next() => _goTo(_index + 1);
  void _prev() => _goTo(_index - 1);

  Future<void> _delete(StoryModel story) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar aviso'),
        content: const Text('¿Eliminar este aviso? No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(storyServiceProvider).deleteStory(story.id);
    if (mounted) _next();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_index];
    final isOwn = story.authorUid == widget.myUid;
    final authorAsync = ref.watch(userProfileProvider(story.authorUid));
    final authorName = switch (authorAsync) {
      AsyncData(value: final u) when u != null => u.displayName,
      _ => 'Profesor',
    };
    final authorPhoto = switch (authorAsync) {
      AsyncData(value: final u)
          when u != null && u.avatarUrl.isNotEmpty =>
        u.avatarUrl,
      _ => null,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final mid = MediaQuery.of(context).size.width / 2;
          d.globalPosition.dx < mid ? _prev() : _next();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Contenido ────────────────────────────────────────────────
            Positioned.fill(
              child: story.type == 'image' && story.imageUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: story.imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                        // Degradado para que el header y el texto sean legibles
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: const Alignment(0, 0.4),
                              colors: [
                                Colors.black.withAlpha(160),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        if (story.content.isNotEmpty)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: const Alignment(0, -0.3),
                                colors: [
                                  Colors.black.withAlpha(160),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : const _TextStoryBackground(),
            ),

            // ── Barra de progreso (top) ───────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(
                    children: List.generate(
                      widget.stories.length,
                      (i) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: i < _index
                              ? LinearProgressIndicator(
                                  value: 1,
                                  backgroundColor:
                                      Colors.white.withAlpha(60),
                                  valueColor:
                                      const AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 2,
                                )
                              : i == _index
                                  ? AnimatedBuilder(
                                      animation: _progress,
                                      builder: (_, _) =>
                                          LinearProgressIndicator(
                                        value: _progress.value,
                                        backgroundColor:
                                            Colors.white.withAlpha(60),
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                                Colors.white),
                                        minHeight: 2,
                                      ),
                                    )
                                  : LinearProgressIndicator(
                                      value: 0,
                                      backgroundColor:
                                          Colors.white.withAlpha(60),
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              Colors.white),
                                      minHeight: 2,
                                    ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Header: autor + tiempo + cerrar ─────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 12, right: 12, top: 22),
                  child: Row(
                    children: [
                      AvatarWidget(
                        photoUrl: authorPhoto,
                        displayName: authorName,
                        uid: story.authorUid,
                        radius: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(authorName,
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(story.timeRemainingLabel,
                                style: GoogleFonts.poppins(
                                    color: Colors.white.withAlpha(160),
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      // Contador de vistas (solo el autor)
                      if (isOwn)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_outlined,
                                  color: Colors.white.withAlpha(200),
                                  size: 16),
                              const SizedBox(width: 4),
                              Text('${story.viewCount}',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white.withAlpha(200),
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      // Nuevo aviso + eliminar (solo el autor)
                      if (isOwn) ...[
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.white),
                          tooltip: 'Nuevo aviso',
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/create-story');
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white),
                          onPressed: () => _delete(story),
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Texto centrado (imagen con texto o solo texto sin fondo) ──
            if (story.content.isNotEmpty)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: story.type == 'image'
                          ? BoxDecoration(
                              color: Colors.black.withAlpha(140),
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      child: Text(
                        story.content,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: story.type == 'image' ? 15 : 22,
                            fontWeight: story.type == 'image'
                                ? FontWeight.w500
                                : FontWeight.w600,
                            height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Fondo para stories de solo texto
class _TextStoryBackground extends StatelessWidget {
  const _TextStoryBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1F35), Color(0xFF1A3A5C), Color(0xFF0D2E1F)],
        ),
      ),
    );
  }
}
