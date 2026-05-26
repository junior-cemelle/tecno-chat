import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/chat_model.dart';
import '../data/models/message_model.dart';
import '../data/models/user_model.dart';
import '../data/services/firestore_service.dart';
import 'auth_provider.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((_) => FirestoreService());

/// Stream en tiempo real de los chats del usuario actual.
final chatsStreamProvider = StreamProvider<List<ChatModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref.read(firestoreServiceProvider).watchChats(uid);
});

/// Perfil de otro usuario por UID (cacheado en el árbol de providers).
final userProfileProvider =
    FutureProvider.family<UserModel?, String>((ref, uid) async {
  return ref.read(firestoreServiceProvider).findUserByUid(uid);
});

/// Lista de perfiles de contactos del usuario actual.
final contactsProvider = FutureProvider<List<UserModel>>((ref) async {
  final me = await ref.watch(currentUserProvider.future);
  if (me == null || me.contactIds.isEmpty) return [];
  return ref
      .read(firestoreServiceProvider)
      .getContactProfiles(me.contactIds);
});

/// Stream en tiempo real de un chat individual.
final chatStreamProvider =
    StreamProvider.family<ChatModel?, String>((ref, chatId) {
  return ref.read(firestoreServiceProvider).watchChat(chatId);
});

/// Stream en tiempo real de los mensajes de un chat.
final messagesStreamProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, chatId) {
  return ref.read(firestoreServiceProvider).watchMessagesList(chatId);
});

/// Stream de chats privados (1-a-1) únicamente. Excluye grupos y asesorías.
final privateChatsStreamProvider = StreamProvider<List<ChatModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref
      .read(firestoreServiceProvider)
      .watchChats(uid)
      .map((chats) =>
          chats.where((c) => c.type == ChatType.private).toList());
});

/// Stream de grupos del usuario (type == 'group'). Excluye asesorías.
final groupsStreamProvider = StreamProvider<List<ChatModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref
      .read(firestoreServiceProvider)
      .watchChats(uid)
      .map((chats) =>
          chats.where((c) => c.type == ChatType.group).toList());
});

/// Stream de chats de asesoría del usuario (type == 'asesoria'). Aplica
/// tanto al asesor como a los alumnos consultantes que estén en
/// `participantIds`.
final asesoriaChatsStreamProvider = StreamProvider<List<ChatModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref
      .read(firestoreServiceProvider)
      .watchChats(uid)
      .map((chats) =>
          chats.where((c) => c.type == ChatType.asesoria).toList());
});
