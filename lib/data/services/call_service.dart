import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/call_model.dart';

class CallService {
  final _db = FirebaseFirestore.instance;

  Future<CallModel> initiateCall({
    required String callerId,
    required String receiverId,
    required CallType type,
  }) async {
    final now = DateTime.now();
    final ref = _db.collection('calls').doc();
    final model = CallModel(
      id: ref.id,
      callerId: callerId,
      receiverId: receiverId,
      participants: [callerId, receiverId],
      type: type,
      status: CallStatus.ringing,
      channelId: ref.id, // Agora channel = Firestore doc ID
      startedAt: now,
    );
    await ref.set(model.toMap());
    return model;
  }

  Future<void> updateStatus(String callId, CallStatus status) {
    return _db.collection('calls').doc(callId).update({
      'status': status.name,
      if (status == CallStatus.ended ||
          status == CallStatus.rejected ||
          status == CallStatus.missed)
        'endedAt': Timestamp.now(),
    });
  }

  Future<void> endCall(String callId, int durationSecs) {
    return _db.collection('calls').doc(callId).update({
      'status': CallStatus.ended.name,
      'endedAt': Timestamp.now(),
      'durationSecs': durationSecs,
    });
  }

  /// Stream de llamada entrante para un usuario (solo status=ringing).
  Stream<CallModel?> watchIncomingCall(String uid) {
    return _db
        .collection('calls')
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .map((s) => s.docs.isEmpty ? null : CallModel.fromDoc(s.docs.first));
  }

  /// Stream de un documento de llamada específico.
  Stream<CallModel?> watchCall(String callId) {
    return _db
        .collection('calls')
        .doc(callId)
        .snapshots()
        .map((s) => s.exists ? CallModel.fromDoc(s) : null);
  }

  /// Historial de llamadas del usuario (ordenado client-side).
  Stream<List<CallModel>> watchCallHistory(String uid) {
    return _db
        .collection('calls')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((s) {
      final list = s.docs.map(CallModel.fromDoc).toList();
      list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return list;
    });
  }
}
