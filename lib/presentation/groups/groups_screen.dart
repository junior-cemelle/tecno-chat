import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/widgets/role_aware_widget.dart';
import '../../data/models/chat_model.dart';
import '../../providers/firestore_provider.dart';

class GroupsScreen extends ConsumerWidget {
  /// Cuando es true actúa como panel de lista en GroupsSplitView (web).
  /// Cambia la navegación a [context.go] para no apilar rutas.
  final bool inSplitView;

  /// ID del grupo actualmente seleccionado (para resaltar en la lista).
  final String? selectedChatId;

  const GroupsScreen({
    super.key,
    this.inSplitView = false,
    this.selectedChatId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Grupos',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
      ),
      body: groupsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, _) =>
            const Center(child: Text('Error al cargar grupos')),
        data: (groups) => groups.isEmpty
            ? _EmptyState()
            : ListView.separated(
                itemCount: groups.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) => _GroupTile(
                  group: groups[i],
                  inSplitView: inSplitView,
                  isSelected: groups[i].id == selectedChatId,
                ),
              ),
      ),
      // FAB visible solo para profesores
      floatingActionButton: TeacherOnly(
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.group_add),
          label: Text('Crear grupo',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          onPressed: () => context.push('/create-group'),
        ),
      ),
    );
  }
}

// ── Tile de grupo ─────────────────────────────────────────────────────────────

class _GroupTile extends StatelessWidget {
  final ChatModel group;
  final bool inSplitView;
  final bool isSelected;

  const _GroupTile({
    required this.group,
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
    final msg = group.lastMessage;
    if (msg == null) return 'Toca para comenzar';
    return switch (msg.type) {
      'image' => '📷 Imagen',
      'video' => '🎥 Video',
      'audio' => '🎵 Audio',
      'gif' => '🎞️ GIF',
      _ => msg.text,
    };
  }

  void _open(BuildContext context) {
    // En split view (web): actualiza URL sin apilar, conserva la lista visible.
    // En móvil: navega a la pantalla de detalle a pantalla completa.
    if (inSplitView) {
      context.go('/groups/${group.id}');
    } else {
      context.push('/chats/${group.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = group.lastMessage?.timestamp ?? group.createdAt;

    return Material(
      color: isSelected
          ? AppColors.green.withAlpha(28)
          : Colors.transparent,
      child: ListTile(
        onTap: () => _open(context),
        selected: isSelected,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: AvatarWidget(
          photoUrl: group.groupAvatarUrl?.isNotEmpty == true
              ? group.groupAvatarUrl
              : null,
          displayName: group.groupName ?? 'Grupo',
          uid: group.id,
          radius: 26,
        ),
        title: Text(
          group.groupName ?? 'Grupo',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
              '${group.participantIds.length} miembros',
              style: GoogleFonts.poppins(
                  fontSize: 10, color: cs.onSurface.withAlpha(100)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Estado vacío ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined,
              size: 80, color: cs.onSurface.withAlpha(60)),
          const SizedBox(height: 16),
          Text('No perteneces a ningún grupo',
              style: GoogleFonts.poppins(
                  fontSize: 16, color: cs.onSurface.withAlpha(160))),
          const SizedBox(height: 8),
          TeacherOnly(
            child: Text('Toca + para crear uno',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: cs.onSurface.withAlpha(100))),
          ),
        ],
      ),
    );
  }
}
