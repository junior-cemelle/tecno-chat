import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatType { private, group }

class LastMessage {
  final String text;
  final String senderId;
  final DateTime timestamp;
  final String type; // 'text' | 'image' | 'video' | 'gif' | 'audio'

  const LastMessage({
    required this.text,
    required this.senderId,
    required this.timestamp,
    required this.type,
  });

  factory LastMessage.fromMap(Map<String, dynamic> m) => LastMessage(
        text: m['text'] ?? '',
        senderId: m['senderId'] ?? '',
        // serverTimestamp() llega null en snapshots de escritura pendiente
        timestamp: (m['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        type: m['type'] ?? 'text',
      );

  Map<String, dynamic> toMap() => {
        'text': text,
        'senderId': senderId,
        'timestamp': Timestamp.fromDate(timestamp),
        'type': type,
      };
}

class ChatModel {
  final String id;
  final ChatType type;
  final List<String> participantIds;
  final DateTime createdAt;
  final LastMessage? lastMessage;

  // Solo grupos
  final String? groupName;
  final String? groupAvatarUrl;
  final String? createdBy;
  final List<String> adminIds;
  final bool hidePhones;
  final String? description;

  const ChatModel({
    required this.id,
    required this.type,
    required this.participantIds,
    required this.createdAt,
    this.lastMessage,
    this.groupName,
    this.groupAvatarUrl,
    this.createdBy,
    this.adminIds = const [],
    this.hidePhones = false,
    this.description,
  });

  bool get isGroup => type == ChatType.group;

  factory ChatModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChatModel(
      id: doc.id,
      type: d['type'] == 'group' ? ChatType.group : ChatType.private,
      participantIds: List<String>.from(d['participantIds'] ?? []),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      lastMessage: d['lastMessage'] != null
          ? LastMessage.fromMap(d['lastMessage'])
          : null,
      groupName: d['groupName'],
      groupAvatarUrl: d['groupAvatarUrl'],
      createdBy: d['createdBy'],
      adminIds: List<String>.from(d['adminIds'] ?? []),
      hidePhones: d['hidePhones'] ?? false,
      description: d['description'],
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'participantIds': participantIds,
        'createdAt': Timestamp.fromDate(createdAt),
        'lastMessage': lastMessage?.toMap(),
        'groupName': groupName,
        'groupAvatarUrl': groupAvatarUrl,
        'createdBy': createdBy,
        'adminIds': adminIds,
        'hidePhones': hidePhones,
        'description': description,
      };
}
