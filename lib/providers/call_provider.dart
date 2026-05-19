import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/call_model.dart';
import '../data/services/call_service.dart';

final callServiceProvider = Provider<CallService>((_) => CallService());

/// Llamada entrante activa para el usuario actual (status == ringing).
final incomingCallProvider = StreamProvider<CallModel?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.read(callServiceProvider).watchIncomingCall(uid);
});

/// Snapshot en tiempo real de una llamada específica.
final callStreamProvider =
    StreamProvider.family<CallModel?, String>((ref, callId) {
  return ref.read(callServiceProvider).watchCall(callId);
});

/// Historial de llamadas del usuario.
final callHistoryProvider = StreamProvider<List<CallModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref.read(callServiceProvider).watchCallHistory(uid);
});
