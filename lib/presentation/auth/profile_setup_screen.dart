import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/fade_background.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/widgets/avatar_url_dialog.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

// ── Constantes de carrera / departamento ─────────────────────────────────────

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

// ── Pantalla principal ────────────────────────────────────────────────────────

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  UserRole _role = UserRole.student;
  String? _career;
  String? _department;
  int _semester = 1;
  String _googlePhotoUrl = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-rellena campos disponibles desde Firebase Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _emailCtrl.text = user.email ?? '';
      _nameCtrl.text = user.displayName ?? '';
      _googlePhotoUrl = user.photoURL ?? '';
      if (user.phoneNumber != null) {
        _phoneCtrl.text = user.phoneNumber!.replaceFirst('+52', '');
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final url = await showAvatarUrlDialog(context, _googlePhotoUrl, FirebaseAuth.instance.currentUser?.uid ?? '');
    if (url != null && mounted) setState(() => _googlePhotoUrl = url);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final user = UserModel(
        uid: uid,
        phone: _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '').isNotEmpty
            ? '+52${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}'
            : (FirebaseAuth.instance.currentUser?.phoneNumber ?? ''),
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        avatarUrl: _googlePhotoUrl,
        role: _role,
        career: _career ?? _careers[0],
        semester: _role == UserRole.student ? _semester : null,
        department: _role == UserRole.teacher ? _department : null,
        isOnline: true,
        lastSeen: DateTime.now(),
        contactIds: [],
        createdAt: DateTime.now(),
      );

      await ref.read(authServiceProvider).saveUserProfile(user);
      // Invalida el caché para que MainShell encuentre el perfil recién creado
      ref.invalidate(currentUserProvider);
      if (mounted) context.go('/chats');
    } catch (e) {
      if (mounted) {
        _snack('Error al guardar: $e');
        setState(() => _saving = false);
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const FadeBackground(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000D1A),
                  Color(0xBB000D1A),
                  Color(0xF0000D1A),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  // En web la ventana puede ser muy ancha; limitamos el card
                  // a un ancho cómodo de formulario (520) y lo centramos para
                  // que los inputs no se estiren a lo ancho de toda la
                  // pantalla. En móvil el card sigue ocupando el ancho
                  // disponible (porque siempre es menor a 520).
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      _GlassCard(
                        formKey: _formKey,
                        nameCtrl: _nameCtrl,
                        emailCtrl: _emailCtrl,
                        phoneCtrl: _phoneCtrl,
                        role: _role,
                        career: _career,
                        department: _department,
                        semester: _semester,
                        googlePhotoUrl: _googlePhotoUrl,
                        saving: _saving,
                        onPickAvatar: _pickAvatar,
                        onRoleChanged: (r) => setState(() => _role = r),
                        onCareerChanged: (c) => setState(() => _career = c),
                        onDepartmentChanged: (d) =>
                            setState(() => _department = d),
                        onSemesterChanged: (s) =>
                            setState(() => _semester = s),
                        onSave: _save,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta glassmorphism ─────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final UserRole role;
  final String? career;
  final String? department;
  final int semester;
  final String googlePhotoUrl;
  final bool saving;
  final VoidCallback onPickAvatar;
  final ValueChanged<UserRole> onRoleChanged;
  final ValueChanged<String?> onCareerChanged;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<int> onSemesterChanged;
  final VoidCallback onSave;

  const _GlassCard({
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.role,
    required this.career,
    required this.department,
    required this.semester,
    required this.googlePhotoUrl,
    required this.saving,
    required this.onPickAvatar,
    required this.onRoleChanged,
    required this.onCareerChanged,
    required this.onDepartmentChanged,
    required this.onSemesterChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final phoneFromAuth =
        FirebaseAuth.instance.currentUser?.phoneNumber != null;

    // BackdropFilter eliminado: produce artefactos de "estiramiento" dentro de
    // SingleChildScrollView (bug conocido de Flutter). Color sólido equivalente.
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(111, 15, 37, 63),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Título ────────────────────────────────────────────
                Text(
                  'Completa tu perfil',
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ingresa tus datos institucionales para continuar',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 24),

                // ── Avatar ────────────────────────────────────────────
                Center(
                  child: _AvatarPicker(
                    photoUrl: googlePhotoUrl,
                    displayName: nameCtrl.text,
                    uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                    onTap: onPickAvatar,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Nombre ────────────────────────────────────────────
                _GlassInput(
                  controller: nameCtrl,
                  label: 'Nombre completo',
                  icon: Icons.person_outline,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),

                // ── Correo ────────────────────────────────────────────
                _GlassInput(
                  controller: emailCtrl,
                  label: 'Correo institucional',
                  icon: Icons.email_outlined,
                  hint: 'usuario@itcelaya.edu.mx',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    if (!v.contains('@')) return 'Correo inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ── Teléfono (editable solo si vino por Google) ───────
                _GlassInput(
                  controller: phoneCtrl,
                  label: phoneFromAuth
                      ? 'Teléfono (verificado)'
                      : 'Teléfono (opcional)',
                  icon: Icons.phone_outlined,
                  hint: '461 000 0000',
                  keyboardType: TextInputType.phone,
                  readOnly: phoneFromAuth,
                  
                ),
                const SizedBox(height: 20),

                // ── Selector de rol ───────────────────────────────────
                Text('Soy',
                    style: GoogleFonts.poppins(
                        color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _RoleChip(
                      label: 'Alumno',
                      icon: Icons.school_outlined,
                      selected: role == UserRole.student,
                      onTap: () => onRoleChanged(UserRole.student),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RoleChip(
                      label: 'Profesor',
                      icon: Icons.person_4_outlined,
                      selected: role == UserRole.teacher,
                      onTap: () => onRoleChanged(UserRole.teacher),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // ── Campos dinámicos por rol ──────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: role == UserRole.student
                      ? _StudentFields(
                          key: const ValueKey('student'),
                          career: career,
                          semester: semester,
                          onCareerChanged: onCareerChanged,
                          onSemesterChanged: onSemesterChanged,
                        )
                      : _TeacherFields(
                          key: const ValueKey('teacher'),
                          department: department,
                          onDepartmentChanged: onDepartmentChanged,
                        ),
                ),
                const SizedBox(height: 28),

                // ── Botón guardar ─────────────────────────────────────
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: saving ? null : onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text('Guardar y continuar',
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

// ── Campos alumno ─────────────────────────────────────────────────────────────

class _StudentFields extends StatelessWidget {
  final String? career;
  final int semester;
  final ValueChanged<String?> onCareerChanged;
  final ValueChanged<int> onSemesterChanged;

  const _StudentFields({
    super.key,
    required this.career,
    required this.semester,
    required this.onCareerChanged,
    required this.onSemesterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassDropdown<String>(
          key: ValueKey('career_$career'),
          initialValue: career,
          label: 'Carrera',
          icon: Icons.book_outlined,
          items: _careers,
          itemLabel: (c) => c,
          onChanged: onCareerChanged,
          validator: (v) => v == null ? 'Selecciona una carrera' : null,
        ),
        const SizedBox(height: 12),
        _GlassDropdown<int>(
          key: ValueKey('semester_$semester'),
          initialValue: semester.clamp(1, 15),
          label: 'Semestre',
          icon: Icons.calendar_today_outlined,
          items: List.generate(15, (i) => i + 1),
          itemLabel: (s) => '$s° Semestre',
          onChanged: (v) => onSemesterChanged(v ?? 1),
        ),
      ],
    );
  }
}

// ── Campos profesor ───────────────────────────────────────────────────────────

class _TeacherFields extends StatelessWidget {
  final String? department;
  final ValueChanged<String?> onDepartmentChanged;

  const _TeacherFields({
    super.key,
    required this.department,
    required this.onDepartmentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassDropdown<String>(
      key: ValueKey('dept_$department'),
      initialValue: department,
      label: 'Departamento',
      icon: Icons.business_outlined,
      items: _departments,
      itemLabel: (d) => d,
      onChanged: onDepartmentChanged,
      validator: (v) => v == null ? 'Selecciona un departamento' : null,
    );
  }
}

// ── Widgets reutilizables ─────────────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  final String photoUrl;
  final String displayName;
  final String uid;
  final VoidCallback onTap;

  const _AvatarPicker({
    required this.photoUrl,
    required this.displayName,
    required this.uid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          AvatarWidget(
            photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
            displayName: displayName,
            uid: uid,
            radius: 45,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(60), width: 1),
              ),
              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final bool readOnly;

  const _GlassInput({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.readOnly = false,
    
  });

  @override
  Widget build(BuildContext context) {
    // Sin ClipRRect+BackdropFilter por campo: el blur de la tarjeta es suficiente
    // y evita el clipping del label flotante y la transparencia en scroll.
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: GoogleFonts.poppins(
          color: readOnly ? Colors.white54 : Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
        hintStyle: GoogleFonts.poppins(color: Colors.white30, fontSize: 14),
        floatingLabelStyle:
            GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.white38, size: 20)
            : null,
        contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        filled: true,
        fillColor: Colors.white.withAlpha(28),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withAlpha(55)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withAlpha(55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle:
            GoogleFonts.poppins(color: AppColors.error, fontSize: 11),
      ),
      validator: validator,
    );
  }
}

class _GlassDropdown<T> extends StatelessWidget {
  final T? initialValue;
  final String label;
  final IconData? icon;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;

  const _GlassDropdown({
    super.key,
    required this.initialValue,
    required this.label,
    this.icon,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      isExpanded: true,
      dropdownColor: AppColors.darkCard,
      icon: const Icon(Icons.keyboard_arrow_down,
          color: Colors.white54, size: 20),
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
        floatingLabelStyle:
            GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.white38, size: 20)
            : null,
        contentPadding: const EdgeInsets.fromLTRB(16, 18, 12, 14),
        filled: true,
        fillColor: Colors.white.withAlpha(28),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withAlpha(55)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withAlpha(55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle:
            GoogleFonts.poppins(color: AppColors.error, fontSize: 11),
      ),
      items: items
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(
                  itemLabel(item),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style:
                      GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                ),
              ))
          .toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withAlpha(60)
              : Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.white.withAlpha(45),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? Colors.white : Colors.white54, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: selected ? Colors.white : Colors.white54,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
