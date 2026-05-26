import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/asesoria_models.dart';
import '../../data/models/user_model.dart';
import '../../data/services/asesoria_service.dart';
import '../../providers/asesoria_provider.dart';
import '../../providers/auth_provider.dart';

/// Pantalla "Mis asesorías" del asesor. Lista todas las asesorías donde el
/// usuario actual es el asesor, sin importar el status. Cada card es un
/// ExpansionTile que muestra:
///  - solicitudes pendientes (con accept/reject inline)
///  - alumnos aceptados
///  - botón "Marcar como completada" (si aplica)
///  - mensaje informativo según status (esperando gerente, finalizada, etc.)
class MyAsesoriasScreen extends ConsumerWidget {
  const MyAsesoriasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis asesorías'),
        actions: [
          IconButton(
            tooltip: 'Solicitar nueva asesoría',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/asesorias/apply'),
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, _) =>
            const Center(child: Text('Error cargando perfil')),
        data: (user) {
          if (user == null) return const SizedBox.shrink();
          return _Body(asesor: user);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final UserModel asesor;
  const _Body({required this.asesor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asesoriasAsync =
        ref.watch(asesoriasByAdvisorProvider(asesor.uid));

    return asesoriasAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.green)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (asesorias) {
        if (asesorias.isEmpty) {
          return _empty(context);
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: asesorias.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) =>
                  _AsesoriaCard(asesoria: asesorias[i], asesor: asesor),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined,
                size: 56, color: cs.onSurface.withAlpha(110)),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes asesorías.',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Postula como asesor para empezar a recibir consultas de tus compañeros.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: cs.onSurface.withAlpha(170)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Solicitar ser asesor'),
              onPressed: () => context.push('/asesorias/apply'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card de una asesoría del asesor ────────────────────────────────────────

class _AsesoriaCard extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel asesor;
  const _AsesoriaCard({required this.asesoria, required this.asesor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: asesoria.status == AsesoriaStatus.approved,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding:
              const EdgeInsets.fromLTRB(14, 0, 14, 12),
          // Title: usamos Flexible (no Expanded) y ponemos el chip como
          // `trailing` para no forzar a la Row interna del ExpansionTile
          // a un ancho infinito al expandirse.
          title: Text(
            asesoria.materia,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: _subtitleFor(context),
          trailing: _StatusChip(status: asesoria.status),
          children: [
            // SizedBox(width: ∞) ancla el ancho del hijo al espacio disponible
            // del ExpansionTile; previene que un Column con stretch interno
            // intente expandirse sin límite si el árbol intermedio cambia.
            SizedBox(
              width: double.infinity,
              child: _StatusBlock(asesoria: asesoria, asesor: asesor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subtitleFor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = GoogleFonts.poppins(
        fontSize: 11, color: cs.onSurface.withAlpha(160));
    switch (asesoria.status) {
      case AsesoriaStatus.pending:
        return Text('Esperando revisión del gerente', style: style);
      case AsesoriaStatus.rejected:
        return Text('Solicitud rechazada', style: style);
      case AsesoriaStatus.approved:
        return Text(
            '${asesoria.studentUids.length}/${asesoria.capacidad} alumnos · '
            'semestre objetivo ${asesoria.semestreObjetivo}',
            style: style);
      case AsesoriaStatus.completed:
        return Text('Esperando finalización del gerente', style: style);
      case AsesoriaStatus.finalized:
        return Text(
            'Asesoría finalizada · ${asesoria.studentUids.length} alumnos atendidos',
            style: style);
    }
  }
}

class _StatusChip extends StatelessWidget {
  final AsesoriaStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AsesoriaStatus.pending => ('Pendiente', Colors.orange.shade700),
      AsesoriaStatus.approved => ('Activa', AppColors.green),
      AsesoriaStatus.rejected => ('Rechazada', AppColors.error),
      AsesoriaStatus.completed => ('Por finalizar', AppColors.primary),
      AsesoriaStatus.finalized => ('Finalizada', Colors.grey.shade600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

// ── Bloque del cuerpo (varía según status) ─────────────────────────────────

class _StatusBlock extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel asesor;
  const _StatusBlock({required this.asesoria, required this.asesor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (asesoria.status) {
      case AsesoriaStatus.pending:
        return _infoCard(
            context,
            'El gerente revisará tu solicitud y definirá la capacidad. '
            'Recibirás acceso al chat de asesoría cuando alguien sea aceptado.');
      case AsesoriaStatus.rejected:
        return _infoCard(
            context,
            asesoria.rejectionReason?.isNotEmpty == true
                ? 'Motivo: ${asesoria.rejectionReason}'
                : 'Tu solicitud fue rechazada por el gerente.',
            isError: true);
      case AsesoriaStatus.approved:
        return _ApprovedBlock(asesoria: asesoria, asesor: asesor);
      case AsesoriaStatus.completed:
        return _infoCard(
            context,
            'Marcaste la asesoría como completada. El gerente la revisará '
            'y dará el visto bueno para finalizarla.');
      case AsesoriaStatus.finalized:
        return _infoCard(context,
            'Esta asesoría fue finalizada. El chat queda como histórico.');
    }
  }

  Widget _infoCard(BuildContext context, String text,
      {bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    final color = isError ? AppColors.error : cs.onSurface;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 11.5, color: color.withAlpha(200))),
    );
  }
}

// ── Bloque approved: requests pendientes + alumnos + acción "completar" ───

class _ApprovedBlock extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel asesor;
  const _ApprovedBlock({required this.asesoria, required this.asesor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sin crossAxisAlignment.stretch — los hijos que necesitan full-width se
    // envuelven explícitamente con Align/SizedBox. Stretch genérico tiende a
    // propagar constraints inesperados al combinarse con ExpansionTile.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Solicitudes pendientes
        _PendingRequestsList(asesoria: asesoria, asesor: asesor),
        const SizedBox(height: 12),

        // Alumnos aceptados
        _Label('Alumnos aceptados (${asesoria.studentUids.length})'),
        const SizedBox(height: 4),
        if (asesoria.studentUids.isEmpty)
          Text(
            'Aún no has aceptado a ningún alumno.',
            style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150)),
          )
        else
          ...asesoria.studentUids.map((uid) => _UserLine(uid: uid)),

        const SizedBox(height: 14),

        // Acciones (chat + completar). Wrap permite que se acomoden en una o
        // dos líneas según el ancho disponible sin requerir Expanded.
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (asesoria.chatId != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Abrir chat'),
                // Salta al branch específico de chats de asesoría
                // (no a /chats genérico) para que aparezca seleccionado
                // en su propia sección del sidebar.
                onPressed: () =>
                    context.go('/asesoria-chats/${asesoria.chatId}'),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Marcar completada'),
              onPressed: asesoria.studentUids.isEmpty
                  ? null
                  : () => _markCompleted(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _markCompleted(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar asesoría como completada'),
        content: const Text(
            'El gerente revisará y dará el visto bueno. Los alumnos siguen '
            'apareciendo en el chat aunque la asesoría se finalice.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar completada'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(asesoriaServiceProvider).markCompleted(
            advisor: asesor,
            asesoriaId: asesoria.id,
          );
    } on AsesoriaException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }
}

class _PendingRequestsList extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel asesor;
  const _PendingRequestsList(
      {required this.asesoria, required this.asesor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync =
        ref.watch(pendingRequestsForAsesoriaProvider(asesoria.id));
    final cs = Theme.of(context).colorScheme;

    return pendingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (requests) {
        if (requests.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('Solicitudes pendientes'),
              const SizedBox(height: 4),
              Text(
                'No tienes solicitudes nuevas.',
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: cs.onSurface.withAlpha(150)),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Label('Solicitudes pendientes (${requests.length})'),
            const SizedBox(height: 6),
            for (final r in requests)
              SizedBox(
                width: double.infinity,
                child: _RequestTile(request: r, asesor: asesor),
              ),
          ],
        );
      },
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  final AsesoriaRequest request;
  final UserModel asesor;
  const _RequestTile({required this.request, required this.asesor});

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(asesoriaServiceProvider).acceptStudentRequest(
            advisor: widget.asesor,
            requestId: widget.request.id,
          );
    } on AsesoriaException catch (e) {
      if (mounted) _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(asesoriaServiceProvider).rejectStudentRequest(
            advisor: widget.asesor,
            requestId: widget.request.id,
          );
    } on AsesoriaException catch (e) {
      if (mounted) _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.request;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.onSurface.withAlpha(30)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserLine(uid: r.studentUid, compact: true),
          if (r.mensaje != null && r.mensaje!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${r.mensaje}"',
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withAlpha(170)),
            ),
          ],
          const SizedBox(height: 8),
          // Wrap: las acciones se acomodan automáticamente sin necesidad de
          // Expanded/Flex que puedan propagar constraints inesperados.
          Align(
            alignment: Alignment.centerRight,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.error, size: 14),
                        label: const Text('Rechazar',
                            style: TextStyle(color: AppColors.error)),
                        onPressed: _reject,
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.check_rounded, size: 14),
                        label: const Text('Aceptar'),
                        onPressed: _accept,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// FutureProvider local que cachea user lookups por uid.
final _userProvider =
    FutureProvider.family<UserModel?, String>((ref, uid) {
  return ref.read(asesoriaServiceProvider).getUser(uid);
});

class _UserLine extends ConsumerWidget {
  final String uid;
  final bool compact;
  const _UserLine({required this.uid, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final userAsync = ref.watch(_userProvider(uid));
    final fontSize = compact ? 12.5 : 12.0;
    return userAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text('Cargando…',
            style: GoogleFonts.poppins(
                fontSize: fontSize, color: cs.onSurface.withAlpha(140))),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text('Alumno: $uid',
            style: GoogleFonts.poppins(fontSize: fontSize)),
      ),
      data: (u) => Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 0 : 3),
        child: Row(
          children: [
            Icon(Icons.person_outline,
                size: 14, color: cs.onSurface.withAlpha(160)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                u == null
                    ? 'Alumno desconocido'
                    : '${u.displayName} · ${u.semester ?? '?'}º sem',
                style: GoogleFonts.poppins(
                    fontSize: fontSize,
                    fontWeight:
                        compact ? FontWeight.w600 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(170)));
  }
}
