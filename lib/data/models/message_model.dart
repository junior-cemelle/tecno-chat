import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, gif, audio, emoji }
enum MessageStatus { sent, delivered, read }

class MessageModel {
  final String id;
  final String senderId;
  final MessageType type;
  final String content;      // texto, URL de media, o URL de audio
  final String? thumbnailUrl;
  final DateTime timestamp;
  final MessageStatus status;
  final List<String> readBy;
  final String? replyToId;
  final List<String> deletedForIds;
  final List<double> waveformData; // Amplitudes normalizadas 0.0-1.0 para audio

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.type,
    required this.content,
    this.thumbnailUrl,
    required this.timestamp,
    required this.status,
    this.readBy = const [],
    this.replyToId,
    this.deletedForIds = const [],
    this.waveformData = const [],
  });

  factory MessageModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == (d['type'] ?? 'text'),
        orElse: () => MessageType.text,
      ),
      content: d['content'] ?? '',
      thumbnailUrl: d['thumbnailUrl'],
      // serverTimestamp() puede llegar null brevemente en escrituras pendientes
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      readBy: List<String>.from(d['readBy'] ?? []),
      replyToId: d['replyToId'],
      deletedForIds: List<String>.from(d['deletedForIds'] ?? []),
      waveformData: (d['waveformData'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'type': type.name,
        'content': content,
        'thumbnailUrl': thumbnailUrl,
        'timestamp': Timestamp.fromDate(timestamp),
        'status': status.name,
        'readBy': readBy,
        'replyToId': replyToId,
        'deletedForIds': deletedForIds,
        'waveformData': waveformData,
      };

  bool isVisibleFor(String userId) => !deletedForIds.contains(userId);
}
