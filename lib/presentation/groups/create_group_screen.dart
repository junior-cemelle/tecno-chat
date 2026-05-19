import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _hidePhones = false;
  bool _saving = false;
  final Set<String> _selected = {};
  List<UserModel> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    final myUid = switch (ref.read(currentUserProvider)) {
      AsyncData(:final value) => value?.uid ?? '',
      _ => '',
    };
    final results =
        await ref.read(firestoreServiceProvider).searchUsersByName(q.trim());
    if (!mounted) return;
    setState(() {
      _searchResults = results.where((u) => u.uid != myUid).toList();
      _searching = false;
    });
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('El nombre del grupo es obligatorio');
      return;
    }
    if (_selected.isEmpty) {
      _snack('Agrega al menos un miembro');
      return;
    }
    final me = switch (ref.read(currentUserProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (me == null) return;
    setState(() => _saving = true);
    try {
      final chatId = await ref.read(firestoreServiceProvider).createGroup(
            name: _nameCtrl.text.trim(),
            creatorUid: me.uid,
            memberUids: _selected.toList(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            hidePhones: _hidePhones,
          );
      if (mounted) context.go('/chats/$chatId');
    } catch (e) {
      if (mounted) {
        _snack('Error al crear grupo: $e');
        setState(() => _saving = false);
      }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _toggle(String uid) => setState(() =>
      _selected.contains(uid) ? _selected.remove(uid) : _selected.add(uid));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contacts = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Nuevo grupo',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _create,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.green))
                : Text('Crear',
                    style: GoogleFonts.poppins(
                        color: AppColors.green, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Info ─────────────────────────────────────────────────────────
          _Label('INFORMACIÓN DEL GRUPO'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 50,
            decoration: InputDecoration(
              labelText: 'Nombre *',
              hintText: 'Ej. Tópicos Avanzados 6°B',
              prefixIcon: const Icon(Icons.group),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'Descripción (opcional)',
              prefixIcon: const Icon(Icons.info_outline),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          // ── Ocultar teléfonos ────────────────────────────────────────────
          SwitchListTile(
            value: _hidePhones,
            activeThumbColor: AppColors.primary,
            secondary: const Icon(Icons.phone_locked_outlined),
            title: Text('Ocultar teléfonos a alumnos',
                style: GoogleFonts.poppins(fontSize: 14)),
            subtitle: Text(
              'Los alumnos no verán el número de ningún miembro',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: cs.onSurface.withAlpha(140)),
            ),
            onChanged: (v) => setState(() => _hidePhones = v),
          ),
          const Divider(height: 24),
          // ── Buscar ───────────────────────────────────────────────────────
          _Label('AGREGAR MIEMBROS'
              '${_selected.isNotEmpty ? "  (${_selected.length})" : ""}'),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16, height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)))
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 8),
          // Resultados búsqueda
          if (_searchResults.isNotEmpty) ...[
            _Label('RESULTADOS'),
            ..._searchResults.map((u) =>
                _MemberTile(user: u, selected: _selected.contains(u.uid),
                    onToggle: () => _toggle(u.uid))),
            const Divider(),
          ],
          // Contactos
          _Label('MIS CONTACTOS'),
          contacts.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.green)),
            ),
            error: (_, _) => const Text('Error al cargar contactos'),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Sin contactos registrados',
                        style: GoogleFonts.poppins(
                            color: cs.onSurface.withAlpha(120))))
                : Column(
                    children: list
                        .map((u) => _MemberTile(
                              user: u,
                              selected: _selected.contains(u.uid),
                              onToggle: () => _toggle(u.uid),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: 0.8));
}

class _MemberTile extends StatelessWidget {
  final UserModel user;
  final bool selected;
  final VoidCallback onToggle;
  const _MemberTile(
      {required this.user, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onToggle,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: AvatarWidget(
        photoUrl: user.avatarUrl.isNotEmpty ? user.avatarUrl : null,
        displayName: user.displayName,
        uid: user.uid,
        radius: 20,
      ),
      title: Text(user.displayName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500,
              fontSize: 14)),
      subtitle: Text(
        user.isTeacher
            ? 'Profesor · ${user.department ?? ""}'
            : '${user.career} · ${user.semester ?? ""}° sem.',
        style: GoogleFonts.poppins(fontSize: 11),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Checkbox(
        value: selected,
        activeColor: AppColors.green,
        onChanged: (_) => onToggle(),
      ),
    );
  }
}
