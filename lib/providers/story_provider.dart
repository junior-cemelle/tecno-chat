import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/story_model.dart';
import '../data/services/story_service.dart';

final storyServiceProvider =
    Provider<StoryService>((_) => StoryService());

/// Stories activos visibles para el usuario actual.
///
/// Obtiene los IDs de grupo una sola vez con un Future para evitar
/// que la suscripción a Firestore se recree en cada emisión del chat stream
/// (lo que causaba un parpadeo por el breve estado AsyncLoading).
final storiesProvider = StreamProvider<List<StoryModel>>((ref) async* {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) { yield []; return; }

  // Obtener grupos UNA sola vez — suscripción estable
  final snap = await FirebaseFirestore.instance
      .collection('chats')
      .where('participantIds', arrayContains: uid)
      .where('type', isEqualTo: 'group')
      .get();

  final groupIds = snap.docs.map((d) => d.id).toList();
  if (groupIds.isEmpty) { yield []; return; }

  // Stream continuo de stories para esos grupos
  yield* ref.read(storyServiceProvider).watchActiveStories(groupIds);
});

/// Stories del usuario actual agrupados por autor (para la fila de stories).
final storiesGroupedProvider =
    Provider<Map<String, List<StoryModel>>>((ref) {
  final storiesAsync = ref.watch(storiesProvider);
  final stories = switch (storiesAsync) {
    AsyncData(value: final s) => s,
    _ => <StoryModel>[],
  };

  final map = <String, List<StoryModel>>{};
  for (final story in stories) {
    map.putIfAbsent(story.authorUid, () => []).add(story);
  }
  return map;
});

/// Stories propios del maestro actual.
final myStoriesProvider = StreamProvider<List<StoryModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref.read(storyServiceProvider).watchMyStories(uid);
});
