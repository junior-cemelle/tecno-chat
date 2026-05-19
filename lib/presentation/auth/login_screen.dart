import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/fade_background.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final digits = _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      _snack('Ingresa un número de 10 dígitos');
      return;
    }
    setState(() => _loading = true);

    await ref.read(authServiceProvider).verifyPhone(
      phone: '+52$digits',
      onCodeSent: (vid) {
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
      final cred = await ref.read(authServiceProvider).signInWithGoogle();
      if (cred == null || !mounted) return;
      final uid = cred.user?.uid;
      if (uid == null || !mounted) return;
      // Comprueba perfil antes de navegar para evitar flash en MainShell
      final exists = await ref.read(authServiceProvider).userProfileExists(uid);
      if (!mounted) return;
      context.go(exists ? '/chats' : '/setup');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Fondo animado ───────────────────────────────────────────────
          const FadeBackground(),

          // ── Gradiente oscuro ────────────────────────────────────────────
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

          // ── Contenido centrado verticalmente ────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Margen superior = espacio para el lince que sobresale
                      const SizedBox(height: 80),

                      // ── Formulario + Lince superpuesto ────────────────
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _GlassFormCard(
                            phoneCtrl: _phoneCtrl,
                            loading: _loading,
                            onContinue: _onContinue,
                            onGoogle: _onGoogle,
                          ),
                          // Lince sin contenedor — transparencia del PNG
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

                      // ── Logo TecNM / ITC ─────────────────────────────
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
                    ],
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
  final TextEditingController phoneCtrl;
  final bool loading;
  final VoidCallback onContinue;
  final VoidCallback onGoogle;

  const _GlassFormCard({
    required this.phoneCtrl,
    required this.loading,
    required this.onContinue,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
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
              // ── Título (Poppins, grande, en la parte superior) ────────
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
                'Comunidad del \nTecnológico de Celaya',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 24),

              // ── Campo teléfono ────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GlassChip(
                    child: Text(
                      '+52',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GlassTextField(
                      controller: phoneCtrl,
                      inputFormatters: [_PhoneFormatter()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Botón continuar ───────────────────────────────────────
              _PrimaryBtn(
                  loading: loading, onTap: onContinue, label: 'Continuar'),
              const SizedBox(height: 20),

              // ── Divisor ───────────────────────────────────────────────
              Row(children: [
                Expanded(child: Divider(color: Colors.white.withAlpha(50))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('o',
                      style: GoogleFonts.poppins(
                          color: Colors.white38, fontSize: 13)),
                ),
                Expanded(child: Divider(color: Colors.white.withAlpha(50))),
              ]),
              const SizedBox(height: 16),

              // ── Botón Google ──────────────────────────────────────────
              _GoogleBtn(onTap: loading ? null : onGoogle),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widgets de apoyo ──────────────────────────────────────────────────────────

class _GlassChip extends StatelessWidget {
  final Widget child;
  const _GlassChip({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(45)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final List<TextInputFormatter>? inputFormatters;
  const _GlassTextField({required this.controller, this.inputFormatters});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          maxLength: 12, // 10 dígitos + 2 espacios del formato "XXX XXX XXXX"
          inputFormatters: inputFormatters,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: '461 000 0000',
            hintStyle:
                GoogleFonts.poppins(color: Colors.white38, fontSize: 15),
            counterText: '',
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

// ── Botón Google con logo oficial (font_awesome_flutter) ─────────────────────

class _GoogleBtn extends StatelessWidget {
  final VoidCallback? onTap;
  const _GoogleBtn({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: const Color(0xFFDFE1E5), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo G oficial de Google (multicolor mediante stack)
              _GoogleColorG(),
              const SizedBox(width: 12),
              Text(
                'Continuar con Google',
                style: GoogleFonts.roboto(
                  color: const Color(0xFF3C4043),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo G de Google — SVG oficial con los 4 colores de marca.
class _GoogleColorG extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      AppAssets.logoGoogle,
      width: 24,
      height: 24,
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
    // Solo dígitos, máximo 10
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
