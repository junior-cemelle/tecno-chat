import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ── Usuarios ────────────────────────────────────────────────────────────────

  Future<UserModel?> findUserByPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\s'), '');
    final q = await _db
        .collection('users')
        .where('phone', isEqualTo: clean)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return UserModel.fromDoc(q.docs.first);
  }

  Future<UserModel?> findUserByEmail(String email) async {
    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return UserModel.fromDoc(q.docs.first);
  }

  Future<UserModel?> findUserByUid(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromDoc(doc);
  }

  /// Búsqueda genérica: detecta si es teléfono, email o UID y consulta.
  Future<UserModel?> findUser(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    if (q.startsWith('+') || RegExp(r'^\d{10}$').hasMatch(q)) {
      final phone = q.startsWith('+') ? q : '+52$q';
      return findUserByPhone(phone);
    }
    if (q.contains('@')) return findUserByEmail(q);
    // Asume UID directo (desde QR)
    return findUserByUid(q);
  }

  // ── Contactos ────────────────────────────────────────────────────────────────

  Future<void> addContact(String myUid, String contactUid) async {
    await _db.collection('users').doc(myUid).update({
      'contactIds': FieldValue.arrayUnion([contactUid]),
    });
  }

  Future<List<UserModel>> getContactProfiles(List<String> uids) async {
    if (uids.isEmpty) return [];
    final futures = uids.map((id) => _db.collection('users').doc(id).get());
    final docs = await Future.wait(futures);
    return docs
        .where((d) => d.exists)
        .map(UserModel.fromDoc)
        .toList();
  }

  // ── Chats ───────────────────────────────────────────────────────────────────

  /// ID determinístico para chat privado: sin queries adicionales.
  static String privateId(String a, String b) =>
      ([a, b]..sort()).join('_');

  /// Obtiene o crea un chat privado entre dos usuarios.
  Future<String> getOrCreatePrivateChat(
      String uid1, String uid2) async {
    final chatId = privateId(uid1, uid2);
    final docRef = _db.collection('chats').doc(chatId);
    final doc = await docRef.get();

    if (!doc.exists) {
      final ids = [uid1, uid2]..sort();
      await docRef.set({
        'type': 'private',
        'participantIds': ids,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'adminIds': [],
        'hidePhones': false,
        'groupName': null,
        'groupAvatarUrl': null,
        'createdBy': null,
        'description': null,
      });
    }
    return chatId;
  }

  /// Stream de todos los chats donde el usuario es participante.
  /// Ordenado en cliente para evitar índice compuesto en Firestore.
  Stream<List<ChatModel>> watchChats(String uid) {
    return _db
        .collection('chats')
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final chats = snap.docs.map(ChatModel.fromDoc).toList();
      chats.sort((a, b) {
        final ta = a.lastMessage?.timestamp ?? a.createdAt;
        final tb = b.lastMessage?.timestamp ?? b.createdAt;
        return tb.compareTo(ta);
      });
      return chats;
    });
  }

  /// Stream en tiempo real de un chat individual.
  Stream<ChatModel?> watchChat(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ChatModel.fromDoc(doc);
    });
  }

  /// Stream de mensajes de un chat, ordenados por timestamp.
  Stream<List<MessageModel>> watchMessagesList(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map((snap) => snap.docs.map(MessageModel.fromDoc).toList());
  }

  /// Envía un mensaje y actualiza lastMessage en el chat (batch atómico).
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String content,
    String type = 'text',
    String? thumbnailUrl,
    List<double> waveformData = const [],
  }) async {
    final msgRef = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();
    final batch = _db.batch();
    batch.set(msgRef, {
      'senderId': senderId,
      'type': type,
      'content': content,
      'thumbnailUrl': thumbnailUrl,
      'waveformData': waveformData,
      'timestamp': FieldValue.serverTimestamp(), // reloj del servidor Firebase
      'status': 'sent',
      'readBy': [senderId],
      'replyToId': null,
      'deletedForIds': [],
    });
    batch.update(
      _db.collection('chats').doc(chatId),
      {
        'lastMessage': {
          'text': type == 'text' ? content : '📷 Media',
          'senderId': senderId,
          'timestamp': FieldValue.serverTimestamp(),
          'type': type,
        },
      },
    );
    await batch.commit();
  }

  /// Marca como 'read' todos los mensajes del chat que no son del usuario actual.
  /// Se llama cuando el usuario abre ChatDetailScreen.
  Future<void> markMessagesAsRead(String chatId, String myUid) async {
    // Solo un filtro != permitido por Firestore; el segundo se hace en cliente.
    final snap = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: myUid)
        .get();

    final unread = snap.docs
        .where((d) => (d.data()['status'] as String?) != 'read')
        .toList();

    if (unread.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unread) {
      batch.update(doc.reference, {
        'status': 'read',
        'readBy': FieldValue.arrayUnion([myUid]),
      });
    }
    await batch.commit();
  }

  /// Marca como 'delivered' los mensajes enviados por otros que aún están en 'sent'.
  /// Se llama cuando el usuario tiene la app abierta pero no necesariamente en el chat.
  Future<void> markMessagesAsDelivered(String chatId, String myUid) async {
    final snap = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: myUid)
        .where('status', isEqualTo: 'sent')
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'status': 'delivered'});
    }
    await batch.commit();
  }

  /// Actualiza el lastMessage en el chat al enviar un mensaje.
  Future<void> updateLastMessage(
      String chatId, Map<String, dynamic> lastMsg) async {
    await _db.collection('chats').doc(chatId).update({'lastMessage': lastMsg});
  }

  // ── Grupos ──────────────────────────────────────────────────────────────────

  /// Crea un grupo y devuelve su chatId.
  Future<String> createGroup({
    required String name,
    required String creatorUid,
    required List<String> memberUids,
    String? description,
    String? avatarUrl,
    bool hidePhones = false,
  }) async {
    final ref = _db.collection('chats').doc();
    final members = ({...memberUids}..add(creatorUid)).toList();
    await ref.set({
      'type': 'group',
      'participantIds': members,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'groupName': name.trim(),
      'groupAvatarUrl': avatarUrl,
      'description': description?.trim(),
      'createdBy': creatorUid,
      'adminIds': [creatorUid],
      'hidePhones': hidePhones,
    });
    return ref.id;
  }

  /// Agrega un miembro al grupo.
  Future<void> addGroupMember(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).update({
      'participantIds': FieldValue.arrayUnion([uid]),
    });
  }

  /// Elimina un miembro (y sus roles de admin si los tenía).
  Future<void> removeGroupMember(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).update({
      'participantIds': FieldValue.arrayRemove([uid]),
      'adminIds': FieldValue.arrayRemove([uid]),
    });
  }

  /// El usuario sale del grupo.
  Future<void> leaveGroup(String chatId, String uid) =>
      removeGroupMember(chatId, uid);

  /// Actualiza nombre, descripción, hidePhones o avatar del grupo.
  Future<void> updateGroup(
    String chatId, {
    String? name,
    String? description,
    bool? hidePhones,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['groupName'] = name.trim();
    if (description != null) data['description'] = description.trim();
    if (hidePhones != null) data['hidePhones'] = hidePhones;
    if (avatarUrl != null) data['groupAvatarUrl'] = avatarUrl;
    if (data.isEmpty) return;
    await _db.collection('chats').doc(chatId).update(data);
  }

  /// Búsqueda de usuarios por nombre (prefix). Útil para agregar miembros.
  Future<List<UserModel>> searchUsersByName(String query,
      {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim();
    final snap = await _db
        .collection('users')
        .where('displayName', isGreaterThanOrEqualTo: q)
        .where('displayName', isLessThan: '${q}z')
        .limit(limit)
        .get();
    return snap.docs.map(UserModel.fromDoc).toList();
  }
}
