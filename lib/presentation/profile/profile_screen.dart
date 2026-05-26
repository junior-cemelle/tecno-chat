import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// ignore: unnecessary_import — necesario para TextInputFormatter abajo
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/platform/recaptcha_cleanup.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/widgets/avatar_url_dialog.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart' show AuthException;
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../core/widgets/qr_dialog.dart';
import '../../presentation/shell/app_router.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          // QR personal — para que otros puedan agregarte
          if (switch (userAsync) {
            AsyncData(value: final u) when u != null => true,
            _ => false
          })
            IconButton(
              icon: const Icon(Icons.qr_code_rounded),
              tooltip: 'Mi código QR',
              onPressed: () {
                final u = switch (userAsync) {
                  AsyncData(value: final u) when u != null => u,
                  _ => null,
                };
                if (u != null) showMyQrDialog(context, u);
              },
            ),
          // Editar perfil
          if (switch (userAsync) {
            AsyncData(value: final u) when u != null => true,
            _ => false
          })
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar perfil',
              onPressed: () => context.push('/profile/edit'),
            ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, e) =>
            const Center(child: Text('Error al cargar perfil')),
        data: (user) => user == null
            ? const Center(child: Text('Sin perfil'))
            : _ProfileBody(user: user, themeMode: themeMode),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final UserModel user;
  final ThemeMode themeMode;

  const _ProfileBody({required this.user, required this.themeMode});

  Future<void> _editAvatar(
      BuildContext context, WidgetRef ref, UserModel u) async {
    final newUrl = await showAvatarUrlDialog(context, u.avatarUrl, u.uid);
    if (newUrl == null) return;
    final updated = UserModel(
      uid: u.uid, phone: u.phone, email: u.email,
      displayName: u.displayName, avatarUrl: newUrl,
      role: u.role, career: u.career, semester: u.semester,
      department: u.department, isOnline: u.isOnline,
      lastSeen: u.lastSeen, contactIds: u.contactIds,
      createdAt: u.createdAt,
    );
    await ref.read(authServiceProvider).saveUserProfile(updated);
    ref.invalidate(currentUserProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final surface = cs.surface;

    // En web la ventana puede ser muy ancha; sin un ConstrainedBox los
    // ListTile estiran su trailing (toggles, botones) hasta el borde derecho
    // dejando un hueco enorme contra el título. 720px da un layout cómodo
    // de "página de ajustes" estilo desktop sin perder densidad.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Container(
          color: surface,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Row(
            children: [
              AvatarWidget(
                photoUrl: user.avatarUrl.isNotEmpty ? user.avatarUrl : null,
                displayName: user.displayName,
                uid: user.uid,
                radius: 36,
                onTap: () => _editAvatar(context, ref, user),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: user.isTeacher
                            ? AppColors.primary.withAlpha(30)
                            : AppColors.green.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.isTeacher ? 'Profesor' : 'Alumno',
                        style: TextStyle(
                          color: user.isTeacher
                              ? AppColors.primary
                              : AppColors.greenDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Información académica ───────────────────────────────────────
        _Section(title: 'Información académica', tiles: [
          _InfoTile(
            icon: user.isTeacher
                ? Icons.business_outlined
                : Icons.school_outlined,
            label: user.isTeacher ? 'Departamento' : 'Carrera',
            value: user.isTeacher
                ? (user.department ?? '-')
                : user.career,
          ),
          if (!user.isTeacher && user.semester != null)
            _InfoTile(
              icon: Icons.calendar_today_outlined,
              label: 'Semestre',
              value: '${user.semester}° Semestre',
            ),
          _InfoTile(
            icon: Icons.phone_outlined,
            label: 'Teléfono',
            value: user.phone.isNotEmpty ? user.phone : 'No registrado',
          ),
        ]),
        const SizedBox(height: 8),

        // ── Ajustes ─────────────────────────────────────────────────────
        _Section(title: 'Ajustes', tiles: [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Modo oscuro'),
            value: themeMode == ThemeMode.dark,
            activeThumbColor: AppColors.green,
            onChanged: (v) => ref
                .read(themeProvider.notifier)
                .setMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notificaciones'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ]),
        const SizedBox(height: 8),

        // ── Asesorías ───────────────────────────────────────────────────
        // Visibilidad condicional por rol:
        //   - Alumno: Buscar asesorías (cualquier alumno) y Mis asesorías
        //     (sirve tanto al asesor como al consultante; muestra empty si no
        //     hay nada). Solicitar ser asesor requiere ≥4º sem.
        //   - Teacher con isAsesoriaManager: Gestión de asesorías.
        if (user.isStudent)
          _Section(title: 'Asesorías', tiles: [
            ListTile(
              leading:
                  const Icon(Icons.search, color: AppColors.primary),
              title: const Text('Buscar asesorías'),
              subtitle: Text(
                'Encuentra una asesoría disponible y solicita unirte.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/asesorias/browse'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined,
                  color: AppColors.primary),
              title: const Text('Mis asesorías'),
              subtitle: Text(
                'Gestiona tus asesorías como asesor: solicitudes y alumnos.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/asesorias/mine'),
            ),
            if ((user.semester ?? 0) >= 4)
              ListTile(
                leading: const Icon(Icons.school_outlined,
                    color: AppColors.primary),
                title: const Text('Solicitar ser asesor'),
                subtitle: Text(
                  'Postúlate para asesorar a otros alumnos en una materia.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/asesorias/apply'),
              ),
          ]),
        if (user.isTeacher && user.isAsesoriaManager)
          _Section(title: 'Asesorías', tiles: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.primary),
              title: const Text('Gestión de asesorías'),
              subtitle: Text(
                'Revisa solicitudes, aprueba asesores y finaliza asesorías.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/asesorias/manage'),
            ),
          ]),
        if (user.isStudent ||
            (user.isTeacher && user.isAsesoriaManager))
          const SizedBox(height: 8),

        // ── Cuentas vinculadas ──────────────────────────────────────────
        _Section(title: 'Cuentas vinculadas', tiles: [
          _LinkedAccountTile(
            providerId: 'password',
            icon: Icons.mail_outline,
            label: 'Correo institucional',
          ),
          _LinkedAccountTile(
            providerId: 'phone',
            icon: Icons.phone_iphone_rounded,
            label: 'Teléfono',
          ),
          _LinkedAccountTile(
            providerId: 'google.com',
            svgAsset: 'lib/assets/logos/google.svg',
            label: 'Google',
          ),
        ]),
        const SizedBox(height: 8),

        // ── Cerrar sesión ────────────────────────────────────────────────
        // Material es necesario para que InkWell/ListTile registre
        // eventos de mouse en Flutter web (HTML renderer).
        Material(
          color: surface,
          child: ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Cerrar sesión',
                style: TextStyle(color: AppColors.error)),
            mouseCursor: SystemMouseCursors.click,
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              // routerProvider.go() no depende de context.mounted,
              // evitando el problema de timing en web tras el signOut.
              ref.read(routerProvider).go('/login');
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
        ),
      ),
    );
  }

}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _Section({required this.title, required this.tiles});

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

class _InfoTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500)),
    );
  }
}

// ── Tile de cuenta vinculada (con acción de link/unlink) ─────────────────────

class _LinkedAccountTile extends ConsumerStatefulWidget {
  final String providerId; // 'password' | 'phone' | 'google.com'
  final IconData? icon;
  final String? svgAsset;
  final String label;

  const _LinkedAccountTile({
    required this.providerId,
    this.icon,
    this.svgAsset,
    required this.label,
  }) : assert(icon != null || svgAsset != null,
            'Debe proveerse icon o svgAsset');

  @override
  ConsumerState<_LinkedAccountTile> createState() => _LinkedAccountTileState();
}

class _LinkedAccountTileState extends ConsumerState<_LinkedAccountTile> {
  bool _busy = false;

  /// Devuelve el identifier visible para el provider (email/teléfono),
  /// o null si no está vinculado.
  String? _linkedIdentifier(User user) {
    final info = user.providerData.where(
      (p) => p.providerId == widget.providerId,
    );
    if (info.isEmpty) return null;
    final data = info.first;
    if (widget.providerId == 'phone') {
      return user.phoneNumber ?? data.phoneNumber;
    }
    return data.email ?? user.email;
  }

  Future<void> _onLink() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (widget.providerId) {
        case 'phone':
          await _startPhoneLinkFlow();
          // El flujo sigue en /otp; no marcamos _busy=false aquí porque la
          // pantalla cambia.
          return;
        case 'google.com':
          await ref.read(authServiceProvider).linkGoogle();
          await _refreshAndNotify('Google vinculado correctamente');
          return;
        default:
          // 'password' no es vinculable post-registro desde aquí.
          break;
      }
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onUnlink() async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desvincular ${widget.label}'),
        content: Text(
          '¿Seguro que quieres desvincular tu ${widget.label.toLowerCase()}? '
          'No podrás iniciar sesión con este método hasta volver a vincularlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desvincular',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).unlinkProvider(widget.providerId);
      await _refreshAndNotify('${widget.label} desvinculado');
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshAndNotify(String msg) async {
    if (!mounted) return;
    // Refresca providerData del user actual y el perfil Firestore.
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {
      // Si no se puede recargar, seguimos igualmente.
    }
    ref.invalidate(currentUserProvider);
    _snack(msg, isError: false);
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// Abre un bottom sheet para capturar el teléfono y dispara el OTP en modo
  /// link. Tras codeSent navegamos a /otp con linkMode=true.
  Future<void> _startPhoneLinkFlow() async {
    final phoneCtrl = TextEditingController();
    final formatter = _PhoneFormatter();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
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
                Text('Vincular teléfono',
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Te enviaremos un código SMS para confirmar.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: cs.onSurface.withAlpha(140)),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.onSurface.withAlpha(40)),
                    ),
                    child: Text('+52',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 12,
                      inputFormatters: [formatter],
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
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final digits = phoneCtrl.text
                          .trim()
                          .replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 10) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Ingresa 10 dígitos'),
                          backgroundColor: AppColors.error,
                        ));
                        return;
                      }
                      Navigator.pop(ctx, '+52$digits');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Enviar código',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    phoneCtrl.dispose();
    if (result == null || !mounted) return;

    // Disparar el OTP. onCodeSent navega a /otp en linkMode.
    await ref.read(authServiceProvider).verifyPhone(
      phone: result,
      onCodeSent: (vid) {
        clearRecaptchaWidgets();
        if (!mounted) return;
        context.push('/otp', extra: {
          'verificationId': vid,
          'phone': result,
          'linkMode': true,
          'returnTo': '/profile',
        });
      },
      onError: (msg) {
        if (mounted) _snack(msg, isError: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos userChanges() (no solo authStateChanges) para que el tile
    // re-renderice automáticamente tras linkWithCredential/unlink — si no,
    // habría que hacer hot reload para ver el estado actualizado.
    final userAsync = ref.watch(firebaseUserChangesProvider);
    final user = switch (userAsync) {
      AsyncData(:final value) => value,
      _ => FirebaseAuth.instance.currentUser,
    };
    if (user == null) return const SizedBox.shrink();

    final identifier = _linkedIdentifier(user);
    final isLinked = identifier != null;
    // 'password' es el método principal — no se permite desvincular desde UI
    // (al menos en este iteración) para no romper el login del usuario.
    final canUnlink = isLinked && widget.providerId != 'password';
    final canLink = !isLinked && widget.providerId != 'password';

    return ListTile(
      leading: widget.svgAsset != null
          ? SvgPicture.asset(widget.svgAsset!, width: 24, height: 24)
          : Icon(widget.icon),
      title: Text(widget.label),
      subtitle: Text(
        identifier ?? 'No vinculado',
        style: TextStyle(
          color: isLinked ? null : Theme.of(context).hintColor,
          fontStyle: isLinked ? null : FontStyle.italic,
        ),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : canLink
              ? TextButton(
                  onPressed: _onLink,
                  child: const Text('Vincular'),
                )
              : canUnlink
                  ? IconButton(
                      icon: const Icon(Icons.link_off,
                          color: AppColors.error, size: 20),
                      tooltip: 'Desvincular',
                      onPressed: _onUnlink,
                    )
                  : const Icon(Icons.check_circle,
                      color: AppColors.green, size: 20),
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
