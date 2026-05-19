import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/story_model.dart';

class StoryService {
  final _db = FirebaseFirestore.instance;

  /// Crea un nuevo story/aviso institucional.
  Future<String> createStory({
    required String authorUid,
    required String content,
    required List<String> groupIds,
    String? imageUrl,
    String type = 'text',
  }) async {
    final now = DateTime.now();
    final ref = await _db.collection('stories').add({
      'authorUid': authorUid,
      'content': content,
      'imageUrl': imageUrl,
      'groupIds': groupIds,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'viewedBy': [],
      'type': type,
    });
    return ref.id;
  }

  /// Stream de stories activos visibles para el usuario según sus grupos.
  /// Firestore arrayContainsAny acepta máximo 10 valores.
  Stream<List<StoryModel>> watchActiveStories(List<String> groupIds) {
    if (groupIds.isEmpty) return Stream.value([]);
    final ids = groupIds.take(10).toList();
    return _db
        .collection('stories')
        .where('groupIds', arrayContainsAny: ids)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(StoryModel.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stories propios del maestro (incluyendo expirados recientes).
  Stream<List<StoryModel>> watchMyStories(String authorUid) {
    return _db
        .collection('stories')
        .where('authorUid', isEqualTo: authorUid)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(StoryModel.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Marca un story como visto por el usuario.
  Future<void> markAsViewed(String storyId, String uid) async {
    await _db.collection('stories').doc(storyId).update({
      'viewedBy': FieldValue.arrayUnion([uid]),
    });
  }

  /// Elimina un story (solo el autor puede).
  Future<void> deleteStory(String storyId) async {
    await _db.collection('stories').doc(storyId).delete();
  }
}
