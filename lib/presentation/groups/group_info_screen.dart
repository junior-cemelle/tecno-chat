import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String chatId;
  const GroupInfoScreen({super.key, required this.chatId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  bool _editingName = false;
  bool _uploadingAvatar = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar(String chatId) async {
    final xfile = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 512);
    if (xfile == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final url = await StorageService()
          .uploadGroupAvatar(chatId, xfile);
      await ref
          .read(firestoreServiceProvider)
          .updateGroup(chatId, avatarUrl: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String get _myUid =>
      switch (ref.read(currentUserProvider)) {
        AsyncData(:final value) => value?.uid ?? '',
        _ => '',
      };

  bool _isAdmin(List<String> adminIds) => adminIds.contains(_myUid);

  Future<void> _saveGroupName(String chatId) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(firestoreServiceProvider).updateGroup(chatId, name: name);
    setState(() => _editingName = false);
  }

  Future<void> _toggleHidePhones(String chatId, bool current) async {
    await ref
        .read(firestoreServiceProvider)
        .updateGroup(chatId, hidePhones: !current);
  }

  Future<void> _leave(String chatId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del grupo'),
        content: const Text('¿Seguro que quieres salir de este grupo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salir',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(firestoreServiceProvider).leaveGroup(chatId, _myUid);
    if (mounted) context.go('/groups');
  }

  Future<void> _removeMember(String chatId, String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar miembro'),
        content: Text('¿Eliminar a $name del grupo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(firestoreServiceProvider)
        .removeGroupMember(chatId, uid);
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatStreamProvider(widget.chatId));
    final cs = Theme.of(context).colorScheme;

    return chatAsync.when(
      loading: () => const Scaffold(
          body:
              Center(child: CircularProgressIndicator(color: AppColors.green))),
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('Error'))),
      data: (chat) {
        if (chat == null || !chat.isGroup) {
          return const Scaffold(
              body: Center(child: Text('Grupo no encontrado')));
        }

        final isAdmin = _isAdmin(chat.adminIds);
        final myUser = switch (ref.watch(currentUserProvider)) {
          AsyncData(:final value) => value,
          _ => null,
        };
        final imTeacher = myUser?.isTeacher ?? false;

        // Inicializar los controladores si vacíos
        if (_nameCtrl.text.isEmpty && chat.groupName != null) {
          _nameCtrl.text = chat.groupName!;
        }
        if (_descCtrl.text.isEmpty && chat.description != null) {
          _descCtrl.text = chat.description!;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Información del grupo',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
          body: ListView(
            children: [
              // ── Header ────────────────────────────────────────────────────
              Container(
                color: cs.surface,
                padding: const EdgeInsets.symmetric(
                    vertical: 24, horizontal: 20),
                child: Column(
                  children: [
                    // Avatar tappable para admins
                    GestureDetector(
                      onTap: isAdmin
                          ? () => _pickAndUploadAvatar(chat.id)
                          : null,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          _uploadingAvatar
                              ? const SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: CircularProgressIndicator(
                                      color: AppColors.green, strokeWidth: 3))
                              : AvatarWidget(
                                  photoUrl:
                                      chat.groupAvatarUrl?.isNotEmpty == true
                                          ? chat.groupAvatarUrl
                                          : null,
                                  displayName: chat.groupName ?? 'Grupo',
                                  uid: chat.id,
                                  radius: 40,
                                ),
                          if (isAdmin && !_uploadingAvatar)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 14, color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Nombre editable por admins
                    if (_editingName && isAdmin)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameCtrl,
                              autofocus: true,
                              style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: UnderlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check,
                                color: AppColors.green),
                            onPressed: () =>
                                _saveGroupName(chat.id),
                          ),
                        ],
                      )
                    else
                      GestureDetector(
                        onTap: isAdmin
                            ? () => setState(() => _editingName = true)
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              chat.groupName ?? 'Grupo',
                              style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.edit_outlined,
                                  size: 16,
                                  color: AppColors.textSecondary),
                            ],
                          ],
                        ),
                      ),
                    if (chat.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        chat.description!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: cs.onSurface.withAlpha(160)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${chat.participantIds.length} miembros',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: cs.onSurface.withAlpha(120)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Configuración (solo admins) ───────────────────────────────
              if (isAdmin) ...[
                _SectionTitle('Configuración'),
                Container(
                  color: cs.surface,
                  child: SwitchListTile(
                    secondary: const Icon(Icons.phone_locked_outlined),
                    title: Text('Ocultar teléfonos a alumnos',
                        style: GoogleFonts.poppins(fontSize: 14)),
                    subtitle: Text(
                      'Los alumnos no ven números de teléfono',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: cs.onSurface.withAlpha(140)),
                    ),
                    value: chat.hidePhones,
                    activeThumbColor: AppColors.primary,
                    onChanged: (_) =>
                        _toggleHidePhones(chat.id, chat.hidePhones),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ── Miembros ──────────────────────────────────────────────────
              _SectionTitle(
                  '${chat.participantIds.length} Miembros'),
              Container(
                color: cs.surface,
                child: Column(
                  children: chat.participantIds.map((uid) {
                    final memberAsync =
                        ref.watch(userProfileProvider(uid));
                    return memberAsync.when(
                      loading: () => const ListTile(
                        leading: CircleAvatar(),
                        title: SizedBox(height: 12, width: 80,
                            child: ColoredBox(color: Colors.grey)),
                      ),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (member) {
                        if (member == null) return const SizedBox.shrink();
                        final isMemberAdmin =
                            chat.adminIds.contains(uid);
                        final isMe = uid == _myUid;

                        // Decidir si mostrar teléfono:
                        // - Admin/teacher siempre ve teléfonos
                        // - Estudiante: solo si hidePhones == false
                        final showPhone =
                            (imTeacher || isAdmin) || !chat.hidePhones;

                        return ListTile(
                          leading: AvatarWidget(
                            photoUrl: member.avatarUrl.isNotEmpty
                                ? member.avatarUrl
                                : null,
                            displayName: member.displayName,
                            uid: uid,
                            radius: 22,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${member.displayName}${isMe ? " (Tú)" : ""}',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMemberAdmin)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Admin',
                                      style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.isTeacher
                                    ? 'Profesor · ${member.department ?? ""}'
                                    : '${member.career} · ${member.semester ?? ""}° sem.',
                                style: GoogleFonts.poppins(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (showPhone &&
                                  member.phone.isNotEmpty)
                                Text(member.phone,
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: cs.onSurface
                                            .withAlpha(140))),
                            ],
                          ),
                          // Admin puede eliminar miembros (excepto a sí mismo)
                          trailing: (isAdmin && !isMe)
                              ? IconButton(
                                  icon: const Icon(
                                      Icons.person_remove_outlined,
                                      color: AppColors.error,
                                      size: 20),
                                  onPressed: () => _removeMember(
                                      chat.id, uid, member.displayName),
                                )
                              : null,
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // ── Salir del grupo ───────────────────────────────────────────
              Container(
                color: cs.surface,
                child: ListTile(
                  leading: const Icon(Icons.exit_to_app,
                      color: AppColors.error),
                  title: Text('Salir del grupo',
                      style: GoogleFonts.poppins(
                          color: AppColors.error)),
                  onTap: () => _leave(chat.id),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 0.8),
        ),
      );
}
