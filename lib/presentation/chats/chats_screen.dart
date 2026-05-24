import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/chat_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';
import 'new_chat_sheet.dart';
import '../stories/stories_row.dart';

class ChatsScreen extends ConsumerWidget {
  /// Cuando es true, la pantalla actúa como panel de la lista en el layout
  /// split (web). Cambia la navegación a [context.go] para no apilar rutas.
  final bool inSplitView;

  /// ID del chat actualmente seleccionado (para resaltar en la lista).
  final String? selectedChatId;

  const ChatsScreen({
    super.key,
    this.inSplitView = false,
    this.selectedChatId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(privateChatsStreamProvider);
    final meAsync = ref.watch(currentUserProvider);
    final myUid = switch (meAsync) {
      AsyncData(value: final u) when u != null => u.uid,
      _ => '',
    };

    return Scaffold(
      // En split view el sidebar global ya tiene el branding; aquí mostramos
      // solo "Chats" como título de la lista para no duplicar.
      appBar: AppBar(
        title: Text(
          inSplitView ? 'Chats' : 'TecNM Chat',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          const StoriesRow(),
          Expanded(
            child: chatsAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.green)),
              error: (_, _) => _EmptyState(),
              data: (chats) => chats.isEmpty
                  ? _EmptyState()
                  : ListView.separated(
                      itemCount: chats.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) => _ChatTile(
                        chat: chats[i],
                        myUid: myUid,
                        inSplitView: inSplitView,
                        isSelected: chats[i].id == selectedChatId,
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        tooltip: 'Nuevo chat',
        onPressed: () async {
          final chatId = await showNewChatSheet(context);
          if (chatId != null && context.mounted) {
            // En split view: actualizar URL sin apilar; en móvil: push normal
            if (inSplitView) {
              context.go('/chats/$chatId');
            } else {
              context.push('/chats/$chatId');
            }
          }
        },
        child: const Icon(Icons.chat_rounded),
      ),
    );
  }
}

// ── Tile de cada conversación ─────────────────────────────────────────────────

class _ChatTile extends ConsumerWidget {
  final ChatModel chat;
  final String myUid;
  final bool inSplitView;
  final bool isSelected;

  const _ChatTile({
    required this.chat,
    required this.myUid,
    required this.inSplitView,
    required this.isSelected,
  });

  String get _otherUid => chat.participantIds.firstWhere(
        (id) => id != myUid,
        orElse: () => '',
      );

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('HH:mm').format(dt);
    }
    if (now.difference(dt).inDays < 7) {
      return DateFormat('E', 'es').format(dt);
    }
    return DateFormat('dd/MM/yy').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chat.isGroup) {
      return _buildTile(
        context: context,
        name: chat.groupName ?? 'Grupo',
        subtitle: chat.lastMessage?.text ?? 'Sin mensajes',
        photoUrl: chat.groupAvatarUrl,
        uid: chat.id,
      );
    }

    final otherAsync = ref.watch(userProfileProvider(_otherUid));
    return otherAsync.when(
      loading: () => const ListTile(
        leading: CircleAvatar(backgroundColor: AppColors.darkCard),
        title: SizedBox(
            height: 12,
            width: 100,
            child: ColoredBox(color: AppColors.darkCard)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (user) => _buildTile(
        context: context,
        name: user?.displayName ?? 'Usuario',
        subtitle: _lastMsgText(),
        photoUrl: user?.avatarUrl,
        uid: user?.uid ?? _otherUid,
      ),
    );
  }

  String _lastMsgText() {
    final msg = chat.lastMessage;
    if (msg == null) return 'Toca para comenzar a chatear';
    return switch (msg.type) {
      'image' => '📷 Imagen',
      'video' => '🎥 Video',
      'audio' => '🎵 Audio',
      'gif' => '🎞️ GIF',
      _ => msg.text,
    };
  }

  Widget _buildTile({
    required BuildContext context,
    required String name,
    required String subtitle,
    String? photoUrl,
    required String uid,
  }) {
    final time = chat.lastMessage?.timestamp ?? chat.createdAt;
    final cs = Theme.of(context).colorScheme;

    return Material(
      // Highlight visible cuando el chat está seleccionado (split view)
      color: isSelected
          ? AppColors.green.withAlpha(28)
          : Colors.transparent,
      child: ListTile(
        onTap: () {
          // En split view: actualizar URL sin apilar; en móvil: push normal
          if (inSplitView) {
            context.go('/chats/${chat.id}');
          } else {
            context.push('/chats/${chat.id}');
          }
        },
        selected: isSelected,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: AvatarWidget(
          photoUrl: photoUrl?.isNotEmpty == true ? photoUrl : null,
          displayName: name,
          uid: uid,
          radius: 26,
        ),
        title: Text(
          name,
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontSize: 13, color: cs.onSurface.withAlpha(140)),
        ),
        trailing: Text(
          _formatTime(time),
          style: GoogleFonts.poppins(
              fontSize: 11, color: cs.onSurface.withAlpha(120)),
        ),
      ),
    );
  }
}

// ── Estado vacío ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 80, color: cs.onSurface.withAlpha(60)),
          const SizedBox(height: 16),
          Text('No hay conversaciones aún',
              style: GoogleFonts.poppins(
                  fontSize: 16, color: cs.onSurface.withAlpha(160))),
          const SizedBox(height: 8),
          Text('Toca + para agregar un contacto',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: cs.onSurface.withAlpha(100))),
        ],
      ),
    );
  }
}
