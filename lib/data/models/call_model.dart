import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { video, audio }
enum CallStatus { ringing, accepted, rejected, ended, missed }

class CallModel {
  final String id;
  final String callerId;
  final String receiverId;
  final List<String> participants; // [callerId, receiverId] para queries
  final CallType type;
  final CallStatus status;
  final String channelId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSecs;

  const CallModel({
    required this.id,
    required this.callerId,
    required this.receiverId,
    required this.participants,
    required this.type,
    required this.status,
    required this.channelId,
    required this.startedAt,
    this.endedAt,
    this.durationSecs,
  });

  factory CallModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final caller = d['callerId'] as String? ?? '';
    final receiver = d['receiverId'] as String? ?? '';
    return CallModel(
      id: doc.id,
      callerId: caller,
      receiverId: receiver,
      participants: List<String>.from(
          d['participants'] as List? ?? [caller, receiver]),
      type: d['type'] == 'audio' ? CallType.audio : CallType.video,
      status: CallStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'ringing'),
        orElse: () => CallStatus.ringing,
      ),
      channelId: d['channelId'] ?? '',
      startedAt: (d['startedAt'] as Timestamp).toDate(),
      endedAt: d['endedAt'] != null
          ? (d['endedAt'] as Timestamp).toDate()
          : null,
      durationSecs: d['durationSecs'],
    );
  }

  Map<String, dynamic> toMap() => {
        'callerId': callerId,
        'receiverId': receiverId,
        'participants': participants,
        'type': type.name,
        'status': status.name,
        'channelId': channelId,
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
        'durationSecs': durationSecs,
      };
}
