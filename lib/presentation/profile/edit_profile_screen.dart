import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/widgets/avatar_url_dialog.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

const _careers = [
  'Ingeniería en Sistemas Computacionales',
  'Ingeniería Industrial',
  'Ingeniería Electrónica',
  'Ingeniería Mecatrónica',
  'Ingeniería Química',
  'Ingeniería Civil',
  'Administración',
  'Contaduría',
  'Ingeniería en Gestión Empresarial',
];

const _departments = [
  'Sistemas y Computación',
  'Metal-Mecánica',
  'Ciencias Básicas',
  'Industrial',
  'Electrónica',
  'Química',
  'Económico-Administrativo',
];

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _career;
  String? _department;
  int _semester = 1;
  String _avatarUrl = '';
  bool _saving = false;
  bool _loaded = false;
  UserModel? _original;

  // Teléfono viene de Firebase Auth, no es editable aquí
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = await ref.read(currentUserProvider.future);
    if (user != null && mounted) {
      setState(() {
        _original = user;
        _nameCtrl.text = user.displayName;
        _emailCtrl.text = user.email;
        _phone = user.phone;
        _career = user.career.isNotEmpty ? user.career : null;
        _department = user.department;
        _semester = user.semester ?? 1;
        _avatarUrl = user.avatarUrl;
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    final url = await showAvatarUrlDialog(
        context, _avatarUrl, _original?.uid ?? '');
    if (url != null && mounted) setState(() => _avatarUrl = url);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _original == null) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? _original!.uid;
      final updated = UserModel(
        uid: uid,
        phone: _phone,
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        avatarUrl: _avatarUrl,
        role: _original!.role,
        career: _career ?? _original!.career,
        semester: _original!.role == UserRole.student ? _semester : null,
        department:
            _original!.role == UserRole.teacher ? _department : null,
        isOnline: _original!.isOnline,
        lastSeen: _original!.lastSeen,
        contactIds: _original!.contactIds,
        createdAt: _original!.createdAt,
      );
      await ref.read(authServiceProvider).saveUserProfile(updated);
      ref.invalidate(currentUserProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
        actions: [
          if (_loaded)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Guardar',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.green))
          : Form(
              key: _formKey,
              child: ListView(
                children: [
                  // ── Avatar ───────────────────────────────────────────
                  Container(
                    color: cs.surface,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: GestureDetector(
                        onTap: _changeAvatar,
                        child: Stack(
                          children: [
                            AvatarWidget(
                              photoUrl: _avatarUrl.isNotEmpty
                                  ? _avatarUrl
                                  : null,
                              displayName: _nameCtrl.text,
                              uid: _original?.uid ?? '',
                              radius: 48,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: cs.surface, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt,
                                    size: 15, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // ── Nombre ───────────────────────────────────────────
                  _EditSection(title: 'Información personal', tiles: [
                    _EditTile(
                      label: 'Nombre completo',
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            hintText: 'Tu nombre completo'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                    _EditTile(
                      label: 'Correo institucional',
                      child: TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            hintText: 'usuario@itcelaya.edu.mx'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Requerido';
                          }
                          if (!v.contains('@')) return 'Correo inválido';
                          return null;
                        },
                      ),
                    ),
                    _EditTile(
                      label: 'Teléfono',
                      subtitle: _phone.isNotEmpty
                          ? 'Vinculado a tu cuenta (no editable)'
                          : null,
                      child: Text(
                        _phone.isNotEmpty ? _phone : 'No registrado',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // ── Rol (solo lectura) ────────────────────────────────
                  _EditSection(title: 'Rol institucional', tiles: [
                    _EditTile(
                      label: 'Rol',
                      subtitle: 'El rol solo puede cambiarse por un administrador',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_original?.isTeacher ?? false)
                              ? AppColors.primary.withAlpha(30)
                              : AppColors.green.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (_original?.isTeacher ?? false)
                              ? 'Profesor'
                              : 'Alumno',
                          style: TextStyle(
                            color: (_original?.isTeacher ?? false)
                                ? AppColors.primary
                                : AppColors.greenDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // ── Información académica ─────────────────────────────
                  if (_original?.role == UserRole.student)
                    _EditSection(title: 'Información académica', tiles: [
                      _EditTile(
                        label: 'Carrera',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('career_$_career'),
                          initialValue: _career,
                          isExpanded: true,
                          items: _careers
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) => setState(() => _career = v),
                          validator: (v) =>
                              v == null ? 'Selecciona una carrera' : null,
                          decoration: const InputDecoration(
                              hintText: 'Selecciona tu carrera'),
                        ),
                      ),
                      _EditTile(
                        label: 'Semestre',
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('semester_$_semester'),
                          initialValue: _semester,
                          items: List.generate(
                            9,
                            (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('${i + 1}° Semestre')),
                          ),
                          onChanged: (v) =>
                              setState(() => _semester = v ?? 1),
                        ),
                      ),
                    ])
                  else
                    _EditSection(title: 'Información académica', tiles: [
                      _EditTile(
                        label: 'Departamento',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('dept_$_department'),
                          initialValue: _department,
                          isExpanded: true,
                          items: _departments
                              .map((d) => DropdownMenuItem(
                                  value: d, child: Text(d)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _department = v),
                          validator: (v) => v == null
                              ? 'Selecciona un departamento'
                              : null,
                          decoration: const InputDecoration(
                              hintText: 'Selecciona tu departamento'),
                        ),
                      ),
                    ]),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _EditSection extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _EditSection({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        Container(
          color: surface,
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

class _EditTile extends StatelessWidget {
  final String label;
  final Widget child;
  final String? subtitle;
  const _EditTile(
      {required this.label, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          child,
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const Divider(height: 20),
        ],
      ),
    );
  }
}
