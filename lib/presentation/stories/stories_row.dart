import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/story_model.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';
import '../../providers/story_provider.dart';
import '../stories/story_viewer_screen.dart';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final grouped = ref.watch(storiesGroupedProvider);
    final isTeacher = ref.watch(isTeacherProvider);
    final myStoriesAsync = ref.watch(myStoriesProvider);
    final myStories = switch (myStoriesAsync) {
      AsyncData(value: final s) => s,
      _ => <StoryModel>[],
    };

    // Si no es profesor y no hay stories visibles, no mostrar nada
    final hasContent = isTeacher || grouped.isNotEmpty;
    if (!hasContent) return const SizedBox.shrink();

    final authorUids = grouped.keys.toList();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                // ── Mis avisos (solo profesores) ──────────────────────
                if (isTeacher)
                  _MyStoryCircle(
                    myUid: myUid,
                    hasActiveStory: myStories.isNotEmpty,
                    onTap: () {
                      if (myStories.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryViewerScreen(
                              stories: myStories,
                              myUid: myUid,
                            ),
                          ),
                        );
                      } else {
                        context.push('/create-story');
                      }
                    },
                    onAdd: () => context.push('/create-story'),
                  ),

                // ── Stories de otros profesores ───────────────────────
                ...authorUids
                    .where((uid) => uid != myUid)
                    .map((uid) {
                  final stories = grouped[uid]!;
                  final allSeen = stories.every((s) => s.isViewedBy(myUid));
                  final firstUnseen = stories.indexWhere(
                      (s) => !s.isViewedBy(myUid));
                  return _AuthorCircle(
                    authorUid: uid,
                    allSeen: allSeen,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoryViewerScreen(
                          stories: stories,
                          myUid: myUid,
                          initialIndex:
                              firstUnseen >= 0 ? firstUnseen : 0,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

// ── Círculo de "Mis avisos" (para el profesor) ─────────────────────────────────

class _MyStoryCircle extends ConsumerWidget {
  final String myUid;
  final bool hasActiveStory;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _MyStoryCircle({
    required this.myUid,
    required this.hasActiveStory,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final photoUrl = switch (userAsync) {
      AsyncData(value: final u) when u != null && u.avatarUrl.isNotEmpty =>
        u.avatarUrl,
      _ => null,
    };
    final name = switch (userAsync) {
      AsyncData(value: final u) when u != null => u.displayName,
      _ => 'Yo',
    };

    return _StoryCircleBase(
      label: 'Mis avisos',
      ringColor: hasActiveStory ? AppColors.primary : Colors.transparent,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          AvatarWidget(
            photoUrl: photoUrl,
            displayName: name,
            uid: myUid,
            radius: 26,
          ),
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Círculo de un autor ────────────────────────────────────────────────────────

class _AuthorCircle extends ConsumerWidget {
  final String authorUid;
  final bool allSeen;
  final VoidCallback onTap;

  const _AuthorCircle({
    required this.authorUid,
    required this.allSeen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(authorUid));
    final photoUrl = switch (userAsync) {
      AsyncData(value: final u) when u != null && u.avatarUrl.isNotEmpty =>
        u.avatarUrl,
      _ => null,
    };
    final name = switch (userAsync) {
      AsyncData(value: final u) when u != null =>
        u.displayName.split(' ').first,
      _ => '…',
    };

    return _StoryCircleBase(
      label: name,
      ringColor: allSeen
          ? Colors.grey.withAlpha(120)
          : AppColors.green,
      onTap: onTap,
      child: AvatarWidget(
        photoUrl: photoUrl,
        displayName: name,
        uid: authorUid,
        radius: 26,
      ),
    );
  }
}

// ── Base del círculo de story ─────────────────────────────────────────────────

class _StoryCircleBase extends StatelessWidget {
  final Widget child;
  final String label;
  final Color ringColor;
  final VoidCallback onTap;

  const _StoryCircleBase({
    required this.child,
    required this.label,
    required this.ringColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 2.5),
              ),
              padding: const EdgeInsets.all(2),
              child: child,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 58,
              child: Text(
                label,
                style: GoogleFonts.poppins(fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
