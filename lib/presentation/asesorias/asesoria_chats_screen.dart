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

/// Lista de chats de asesoría — replica el patrón de GroupsScreen pero
/// muestra exclusivamente `ChatType.asesoria`. Indica si soy el asesor o
/// un alumno consultante para distinguir visualmente mi rol en cada chat.
class AsesoriaChatsScreen extends ConsumerWidget {
  /// True cuando vive dentro del split view (web). Cambia push→go.
  final bool inSplitView;
  final String? selectedChatId;

  const AsesoriaChatsScreen({
    super.key,
    this.inSplitView = false,
    this.selectedChatId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(asesoriaChatsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Asesorías',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
      ),
      body: chatsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, _) => const Center(
            child: Text('Error al cargar chats de asesoría')),
        data: (chats) => chats.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                itemCount: chats.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) => _AsesoriaChatTile(
                  chat: chats[i],
                  inSplitView: inSplitView,
                  isSelected: chats[i].id == selectedChatId,
                ),
              ),
      ),
    );
  }
}

class _AsesoriaChatTile extends ConsumerWidget {
  final ChatModel chat;
  final bool inSplitView;
  final bool isSelected;

  const _AsesoriaChatTile({
    required this.chat,
    required this.inSplitView,
    required this.isSelected,
  });

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

  String _lastMsg() {
    final msg = chat.lastMessage;
    if (msg == null) return 'Toca para comenzar la asesoría';
    return switch (msg.type) {
      'image' => '📷 Imagen',
      'video' => '🎥 Video',
      'audio' => '🎵 Audio',
      'gif' => '🎞️ GIF',
      _ => msg.text,
    };
  }

  void _open(BuildContext context) {
    // Mismo patrón que groups: en split view solo cambiamos URL sin apilar.
    if (inSplitView) {
      context.go('/asesoria-chats/${chat.id}');
    } else {
      context.push('/chats/${chat.id}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final time = chat.lastMessage?.timestamp ?? chat.createdAt;
    // Identificar si el usuario actual es el asesor del chat.
    final me = ref.watch(currentUserProvider).value;
    final isAdvisor = me != null && chat.createdBy == me.uid;

    return Material(
      color: isSelected
          ? AppColors.green.withAlpha(28)
          : Colors.transparent,
      child: ListTile(
        onTap: () => _open(context),
        selected: isSelected,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarWidget(
              photoUrl: chat.groupAvatarUrl?.isNotEmpty == true
                  ? chat.groupAvatarUrl
                  : null,
              displayName: chat.groupName ?? 'Asesoría',
              uid: chat.id,
              radius: 26,
            ),
            // Mini-badge de "libro" abajo a la derecha para identificar
            // el tile como asesoría académica.
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: const Icon(Icons.school_outlined,
                    size: 10, color: Colors.white),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                chat.groupName ?? 'Asesoría',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _RoleChip(isAdvisor: isAdvisor),
          ],
        ),
        subtitle: Text(
          _lastMsg(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontSize: 13, color: cs.onSurface.withAlpha(140)),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTime(time),
              style: GoogleFonts.poppins(
                  fontSize: 11, color: cs.onSurface.withAlpha(120)),
            ),
            const SizedBox(height: 4),
            Text(
              '${chat.participantIds.length} participantes',
              style: GoogleFonts.poppins(
                  fontSize: 10, color: cs.onSurface.withAlpha(100)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip "Asesor" / "Alumno" — distingue mi rol en el chat de un solo vistazo.
class _RoleChip extends StatelessWidget {
  final bool isAdvisor;
  const _RoleChip({required this.isAdvisor});

  @override
  Widget build(BuildContext context) {
    final color = isAdvisor ? AppColors.primary : AppColors.green;
    final label = isAdvisor ? 'Asesor' : 'Alumno';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined,
                size: 80, color: cs.onSurface.withAlpha(60)),
            const SizedBox(height: 16),
            Text('Aún no tienes chats de asesoría',
                style: GoogleFonts.poppins(
                    fontSize: 16, color: cs.onSurface.withAlpha(160))),
            const SizedBox(height: 8),
            Text(
              'Aquí aparecerán las asesorías activas en las que '
              'participas como asesor o alumno.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: cs.onSurface.withAlpha(120)),
            ),
          ],
        ),
      ),
    );
  }
}
