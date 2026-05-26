import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart';
import '../../core/platform/recaptcha_cleanup.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/fade_background.dart';
import '../../data/services/auth_service.dart' show AuthException;
import '../../providers/auth_provider.dart';
import '../profile/edit_profile_screen.dart' show kStudentCareers;

/// Login con dos roles:
///  - Alumno: email + password contra el SII (luego sincroniza Firebase Auth)
///  - Profesor: email + password directo a Firebase Auth (sin SII)
///
/// Métodos secundarios (mismo flujo para ambos roles):
///  - Teléfono OTP: solo si el usuario ya vinculó su teléfono post-registro
///  - Google: solo si la cuenta de Google ya está vinculada a un perfil
enum _LoginRole { student, teacher }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  _LoginRole _role = _LoginRole.student;
  bool _loading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Acciones ────────────────────────────────────────────────────────────────

  Future<void> _onSignInWithEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _snack('Ingresa tu correo y contraseña');
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      if (_role == _LoginRole.student) {
        await auth.signInStudent(email: email, password: password);
      } else {
        await auth.signInTeacher(email: email, password: password);
      }
      if (!mounted) return;
      ref.invalidate(currentUserProvider);
      context.go('/chats');
    } on AuthException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onContinueWithPhone() async {
    final digits = _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      _snack('Ingresa un número de 10 dígitos');
      return;
    }
    setState(() => _loading = true);
    await ref.read(authServiceProvider).verifyPhone(
      phone: '+52$digits',
      onCodeSent: (vid) {
        clearRecaptchaWidgets();
        if (!mounted) return;
        setState(() => _loading = false);
        context.push('/otp', extra: {
          'verificationId': vid,
          'phone': '+52$digits',
        });
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _loading = false);
        _snack(msg);
      },
    );
  }

  Future<void> _onGoogle() async {
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (!mounted) return;
      ref.invalidate(currentUserProvider);
      context.go('/chats');
    } on AuthException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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

  void _showPhoneSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PhoneSheet(
        controller: _phoneCtrl,
        loading: _loading,
        onContinue: () {
          Navigator.pop(context);
          _onContinueWithPhone();
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 80),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _GlassFormCard(
                                role: _role,
                                emailCtrl: _emailCtrl,
                                passwordCtrl: _passwordCtrl,
                                loading: _loading,
                                showPassword: _showPassword,
                                onToggleShowPassword: () => setState(
                                    () => _showPassword = !_showPassword),
                                onRoleChanged: (r) =>
                                    setState(() => _role = r),
                                onSignIn: _onSignInWithEmail,
                                onPhone: _showPhoneSheet,
                                onGoogle: _onGoogle,
                              ),
                              Positioned(
                                top: -88,
                                right: -2,
                                child: Image.asset(
                                  AppAssets.logoLince,
                                  width: 182,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: ColoredBox(
                              color: Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Image.asset(
                                  AppAssets.logoLogin,
                                  height: 52,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Este sitio está protegido por reCAPTCHA. '
                            'Aplican la Política de Privacidad y los '
                            'Términos de Servicio de Google.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withAlpha(100),
                            ),
                          ),
                          const SizedBox(height: 12),
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

class _GlassFormCard extends StatelessWidget {
  final _LoginRole role;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool loading;
  final bool showPassword;
  final VoidCallback onToggleShowPassword;
  final ValueChanged<_LoginRole> onRoleChanged;
  final VoidCallback onSignIn;
  final VoidCallback onPhone;
  final VoidCallback onGoogle;

  const _GlassFormCard({
    required this.role,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.loading,
    required this.showPassword,
    required this.onToggleShowPassword,
    required this.onRoleChanged,
    required this.onSignIn,
    required this.onPhone,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    final isStudent = role == _LoginRole.student;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withAlpha(50),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'TecNM \nChat',
                style: GoogleFonts.poppins(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isStudent
                    ? 'Inicia sesión con tu cuenta del SII'
                    : 'Acceso para profesores registrados',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 20),

              // ── Tabs de rol ─────────────────────────────────────────
              _RoleTabs(role: role, onChanged: onRoleChanged),
              const SizedBox(height: 20),

              // ── Email ──────────────────────────────────────────────
              _GlassTextField(
                controller: emailCtrl,
                hint: isStudent
                    ? 'lXXXXXXXX@celaya.tecnm.mx'
                    : 'correo@itcelaya.edu.mx',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline,
              ),
              const SizedBox(height: 12),

              // ── Password ───────────────────────────────────────────
              _GlassTextField(
                controller: passwordCtrl,
                hint: 'Contraseña',
                obscureText: !showPassword,
                prefixIcon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: onToggleShowPassword,
                ),
                onSubmit: onSignIn,
              ),
              const SizedBox(height: 16),

              // ── Botón principal: iniciar sesión ────────────────────
              _PrimaryBtn(
                loading: loading,
                onTap: onSignIn,
                label: 'Iniciar sesión',
              ),
              const SizedBox(height: 20),

              // ── Divisor ────────────────────────────────────────────
              Row(children: [
                Expanded(child: Divider(color: Colors.white.withAlpha(50))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'o continúa con',
                    style: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 12),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white.withAlpha(50))),
              ]),
              const SizedBox(height: 16),

              // ── Login secundario: teléfono + Google ────────────────
              Row(children: [
                Expanded(
                  child: _SecondaryBtn(
                    icon: Icons.phone_iphone_rounded,
                    label: 'Teléfono',
                    onTap: loading ? null : onPhone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SecondaryBtn(
                    iconWidget: SvgPicture.asset(
                      AppAssets.logoGoogle,
                      width: 18,
                      height: 18,
                    ),
                    label: 'Google',
                    onTap: loading ? null : onGoogle,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Estos métodos requieren que ya tengas una cuenta registrada.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 10.5, color: Colors.white38),
                ),
              ),
              // ── Botón DEV ────────────────────────────────────────────
              // TEMPORAL: visible también en release durante la presentación
              // del proyecto para facilitar la prueba de cuentas de alumno
              // sin credenciales reales del SII. Tras la presentación,
              // volver a envolver este bloque en `if (kDebugMode) ...[`
              // para excluirlo del bundle de producción.
              ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                 
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 100,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.person_add_alt_1, size: 16),
                          label: const Text('Dev.'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: BorderSide(
                                color: Colors.orange.withAlpha(180)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: loading
                              ? null
                              : () => _openDevRegisterDialog(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre el dialog dev de registro de alumno de prueba. Visible solo bajo
/// `kDebugMode`.
Future<void> _openDevRegisterDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DevRegisterDialog(),
  );
}

class _DevRegisterDialog extends ConsumerStatefulWidget {
  const _DevRegisterDialog();

  @override
  ConsumerState<_DevRegisterDialog> createState() =>
      _DevRegisterDialogState();
}

class _DevRegisterDialogState extends ConsumerState<_DevRegisterDialog> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _career = kStudentCareers.first;
  int _semester = 5;
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final name = _nameCtrl.text.trim();
    final career = _career;
    if (email.isEmpty || pass.length < 6 || name.isEmpty) {
      setState(() => _errorMsg =
          'Completa todos los campos (password ≥6 caracteres).');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(authServiceProvider).registerStudentDev(
            email: email,
            password: pass,
            displayName: name,
            career: career,
            semester: _semester,
          );
      if (mounted) {
        Navigator.of(context).pop();
        // Después de createUserWithEmailAndPassword Firebase ya autenticó
        // a este usuario — el router redirige solo a /chats.
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.science_outlined,
              color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Text('Cuenta de prueba (DEV)',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Crea o reingresa con un alumno dummy directamente en Firebase, '
                'sin validar contra SII. Si el email ya existe, intenta '
                'iniciar sesión con esa contraseña. Solo disponible en debug.',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: const Color.fromARGB(137, 255, 255, 255)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña (mín. 6)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _career,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Carrera',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: kStudentCareers
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _career = v ?? _career),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _semester,
                decoration: const InputDecoration(
                  labelText: 'Semestre',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: List.generate(15, (i) => i + 1)
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text('$s° Semestre'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _semester = v ?? _semester),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(_errorMsg!,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Crear y entrar'),
        ),
      ],
    );
  }
}

// ── Tabs de rol ───────────────────────────────────────────────────────────────

class _RoleTabs extends StatelessWidget {
  final _LoginRole role;
  final ValueChanged<_LoginRole> onChanged;
  const _RoleTabs({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        Expanded(
          child: _RoleTabBtn(
            label: 'Alumno',
            icon: Icons.school_outlined,
            selected: role == _LoginRole.student,
            onTap: () => onChanged(_LoginRole.student),
          ),
        ),
        Expanded(
          child: _RoleTabBtn(
            label: 'Profesor',
            icon: Icons.person_outline,
            selected: role == _LoginRole.teacher,
            onTap: () => onChanged(_LoginRole.teacher),
          ),
        ),
      ]),
    );
  }
}

class _RoleTabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleTabBtn({
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inputs y botones ──────────────────────────────────────────────────────────

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final VoidCallback? onSubmit;
  const _GlassTextField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffix,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.poppins(color: Colors.white38, fontSize: 14),
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, color: Colors.white54, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.white.withAlpha(20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withAlpha(45)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withAlpha(45)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.green, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  final String label;
  const _PrimaryBtn(
      {required this.loading, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback? onTap;
  const _SecondaryBtn({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.white.withAlpha(disabled ? 10 : 25),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withAlpha(disabled ? 25 : 55), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconWidget != null)
                iconWidget!
              else if (icon != null)
                Icon(icon,
                    size: 18,
                    color: disabled ? Colors.white38 : Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: disabled ? Colors.white38 : Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sheet para ingresar teléfono ──────────────────────────────────────────────

class _PhoneSheet extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onContinue;
  const _PhoneSheet({
    required this.controller,
    required this.loading,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Continuar con teléfono',
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Solo funciona si ya vinculaste tu teléfono a tu cuenta.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: cs.onSurface.withAlpha(140)),
            ),
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: cs.onSurface.withAlpha(40)),
                ),
                child: Text('+52',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 12,
                  inputFormatters: [_PhoneFormatter()],
                  style: GoogleFonts.poppins(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '461 000 0000',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: cs.onSurface.withAlpha(40)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: cs.onSurface.withAlpha(40)),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            _PrimaryBtn(
                loading: loading, onTap: onContinue, label: 'Enviar código'),
          ],
        ),
      ),
    );
  }
}

/// Formatea 10 dígitos como "XXX XXX XXXX" mientras el usuario escribe.
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 10 ? digits.substring(0, 10) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < capped.length; i++) {
      if (i == 3 || i == 6) buf.write(' ');
      buf.write(capped[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
