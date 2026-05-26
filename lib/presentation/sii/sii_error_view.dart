import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/sii_api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sii_provider.dart';
import '../shell/app_router.dart';

/// Vista de error reutilizable por todas las pantallas SII.
///
/// Diferencia 3 escenarios:
///  - sesión expirada / sin JWT → ofrece "Reconectar con SII" (prompt password)
///    + "Cerrar sesión" como fallback
///  - otros errores → "Reintentar"
class SiiErrorView extends ConsumerWidget {
  final Object error;
  final VoidCallback onRetry;
  const SiiErrorView({super.key, required this.error, required this.onRetry});

  bool get _isSessionExpired =>
      error is SiiSessionExpiredException ||
      (error is SiiApiException &&
          (error as SiiApiException).isUnauthorized);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final email = switch (ref.watch(currentUserProvider)) {
      AsyncData(:final value) => value?.email,
      _ => null,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSessionExpired
                    ? Icons.lock_clock_outlined
                    : Icons.cloud_off_rounded,
                size: 56,
                color: AppColors.error.withAlpha(180),
              ),
              const SizedBox(height: 14),
              Text(
                _isSessionExpired
                    ? 'Tu sesión del SII no está activa'
                    : 'No pudimos cargar tus datos',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _isSessionExpired
                    ? (email != null
                        ? 'Para volver a ver tus datos académicos, confirma '
                            'tu contraseña del SII para $email.'
                        : 'Confirma tu contraseña del SII para reconectar.')
                    : '$error',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: cs.onSurface.withAlpha(170)),
              ),
              const SizedBox(height: 18),
              if (_isSessionExpired) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Reconectar con SII'),
                  onPressed: email == null
                      ? null
                      : () => _reconnect(context, ref, email),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Cerrar sesión'),
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    if (context.mounted) {
                      ref.read(routerProvider).go('/login');
                    }
                  },
                ),
              ] else
                FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                  onPressed: onRetry,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reconnect(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SiiPasswordDialog(email: email),
    );
    if (ok != true) return;
    // Invalidar TODOS los providers SII para que cualquier pantalla abierta
    // refresque con el nuevo token (no solo la actual).
    ref.invalidate(siiEstudianteProvider);
    ref.invalidate(siiCalificacionesProvider);
    ref.invalidate(siiKardexProvider);
    ref.invalidate(siiHorariosProvider);
  }
}

/// Diálogo modal que pide la contraseña SII y llama a `refreshSiiToken`.
/// Devuelve `true` si se reconectó correctamente, `false`/`null` si se canceló
/// o falló.
class _SiiPasswordDialog extends ConsumerStatefulWidget {
  final String email;
  const _SiiPasswordDialog({required this.email});

  @override
  ConsumerState<_SiiPasswordDialog> createState() =>
      _SiiPasswordDialogState();
}

class _SiiPasswordDialogState extends ConsumerState<_SiiPasswordDialog> {
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _errorMsg;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(authServiceProvider).refreshSiiToken(
            email: widget.email,
            password: _passCtrl.text,
          );
      if (mounted) Navigator.of(context).pop(true);
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
          _errorMsg = 'Error inesperado: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reconectar con SII'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Confirma tu contraseña institucional para volver a obtener un '
            'token vigente.',
            style: GoogleFonts.poppins(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(widget.email,
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Contraseña SII',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 8),
            Text(_errorMsg!,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy || _passCtrl.text.isEmpty ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Reconectar'),
        ),
      ],
    );
  }
}
