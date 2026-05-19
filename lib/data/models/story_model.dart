import 'package:cloud_firestore/cloud_firestore.dart';

class StoryModel {
  final String id;
  final String authorUid;
  final String content;
  final String? imageUrl;
  final List<String> groupIds;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewedBy;
  final String type; // 'text' | 'image'

  const StoryModel({
    required this.id,
    required this.authorUid,
    required this.content,
    this.imageUrl,
    required this.groupIds,
    required this.createdAt,
    required this.expiresAt,
    required this.viewedBy,
    required this.type,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  int get viewCount => viewedBy.length;

  String get timeRemainingLabel {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.inHours >= 1) return 'Expira en ${remaining.inHours}h';
    return 'Expira en ${remaining.inMinutes}m';
  }

  bool isViewedBy(String uid) => viewedBy.contains(uid);

  factory StoryModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return StoryModel(
      id: doc.id,
      authorUid: d['authorUid'] ?? '',
      content: d['content'] ?? '',
      imageUrl: d['imageUrl'],
      groupIds: List<String>.from(d['groupIds'] ?? []),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      expiresAt: (d['expiresAt'] as Timestamp).toDate(),
      viewedBy: List<String>.from(d['viewedBy'] ?? []),
      type: d['type'] ?? 'text',
    );
  }
}
