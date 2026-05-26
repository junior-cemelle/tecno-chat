import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/platform/download_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/asesoria_models.dart';
import '../../data/models/user_model.dart';
import '../../data/services/asesoria_service.dart';
import '../../providers/asesoria_provider.dart';
import '../../providers/auth_provider.dart';

/// Dashboard del GERENTE DE ASESORÍAS. Dos tabs:
///  - Solicitudes pendientes (asesores aplicando) → aprobar/rechazar
///  - Por finalizar (asesor marcó completada) → finalizar con check
class ManagerDashboardScreen extends ConsumerWidget {
  const ManagerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.green)),
      ),
      error: (_, _) => const Scaffold(
        body: Center(child: Text('Error cargando perfil')),
      ),
      data: (user) {
        if (user == null || !user.isAsesoriaManager) {
          return Scaffold(
            appBar: AppBar(title: const Text('Gestión de asesorías')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Solo el gerente de asesorías puede acceder a este panel.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _DashboardBody(manager: user);
      },
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final UserModel manager;
  const _DashboardBody({required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingAsesoriasProvider);
    final awaitingAsync = ref.watch(awaitingFinalizationProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestión de asesorías'),
          bottom: TabBar(
            indicatorColor: AppColors.green,
            labelColor: AppColors.green,
            tabs: [
              Tab(
                icon: _BadgeIcon(
                  icon: Icons.assignment_ind_outlined,
                  count: pendingAsync.value?.length ?? 0,
                ),
                text: 'Solicitudes',
              ),
              Tab(
                icon: _BadgeIcon(
                  icon: Icons.check_circle_outline,
                  count: awaitingAsync.value?.length ?? 0,
                ),
                text: 'Por finalizar',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ListView(
              async: pendingAsync,
              emptyText:
                  'No hay solicitudes pendientes por revisar.',
              builder: (a) => _PendingTile(asesoria: a, manager: manager),
            ),
            _ListView(
              async: awaitingAsync,
              emptyText:
                  'No hay asesorías esperando finalización.',
              builder: (a) =>
                  _AwaitingFinalizationTile(asesoria: a, manager: manager),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(20),
              ),
              constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _ListView extends StatelessWidget {
  final AsyncValue<List<Asesoria>> async;
  final String emptyText;
  final Widget Function(Asesoria) builder;
  const _ListView({
    required this.async,
    required this.emptyText,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.green)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(160)),
              ),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => builder(items[i]),
            ),
          ),
        );
      },
    );
  }
}

// ── Tile: solicitud pendiente ──────────────────────────────────────────────

class _PendingTile extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel manager;
  const _PendingTile({required this.asesoria, required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Icon(Icons.school_outlined, color: Colors.white),
        ),
        title: Text(asesoria.materia,
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: _AdvisorLine(uid: asesoria.advisorUid),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openReview(context, ref),
      ),
    );
  }

  Future<void> _openReview(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReviewApplicationDialog(
        asesoria: asesoria,
        manager: manager,
      ),
    );
  }
}

// ── Tile: por finalizar ────────────────────────────────────────────────────

class _AwaitingFinalizationTile extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel manager;
  const _AwaitingFinalizationTile(
      {required this.asesoria, required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.greenDark,
          child:
              Icon(Icons.task_alt_outlined, color: Colors.white),
        ),
        title: Text(asesoria.materia,
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AdvisorLine(uid: asesoria.advisorUid),
            Text(
                '${asesoria.studentUids.length} alumno(s) · marcada como completada',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: cs.onSurface.withAlpha(150))),
          ],
        ),
        trailing: FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Finalizar'),
          onPressed: () async {
            try {
              await ref.read(asesoriaServiceProvider).finalize(
                    manager: manager,
                    asesoriaId: asesoria.id,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Asesoría finalizada.'),
                  backgroundColor: AppColors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              }
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
          },
        ),
      ),
    );
  }
}

// Linea de "Asesor: Nombre" que resuelve el nombre del UID.
class _AdvisorLine extends ConsumerWidget {
  final String uid;
  const _AdvisorLine({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futureUser = ref.watch(_advisorUserProvider(uid));
    return futureUser.when(
      loading: () => Text('Cargando…',
          style: GoogleFonts.poppins(
              fontSize: 11.5, color: Colors.grey.shade400)),
      error: (_, _) => Text('Asesor: $uid',
          style: GoogleFonts.poppins(fontSize: 11.5)),
      data: (u) => Text(
        u == null
            ? 'Asesor desconocido'
            : 'Asesor: ${u.displayName} · ${u.semester ?? '?'}º sem',
        style: GoogleFonts.poppins(fontSize: 11.5),
      ),
    );
  }
}

// FutureProvider local — cache por uid mientras viva la pantalla.
final _advisorUserProvider =
    FutureProvider.family<UserModel?, String>((ref, uid) {
  return ref.read(asesoriaServiceProvider).getUser(uid);
});

// ── Dialog: revisar solicitud pendiente ────────────────────────────────────

class _ReviewApplicationDialog extends ConsumerStatefulWidget {
  final Asesoria asesoria;
  final UserModel manager;
  const _ReviewApplicationDialog(
      {required this.asesoria, required this.manager});

  @override
  ConsumerState<_ReviewApplicationDialog> createState() =>
      _ReviewApplicationDialogState();
}

class _ReviewApplicationDialogState
    extends ConsumerState<_ReviewApplicationDialog> {
  final _capacidadCtrl = TextEditingController(text: '5');
  final _semestreCtrl = TextEditingController(text: '1');
  final _rejectReasonCtrl = TextEditingController();
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _capacidadCtrl.dispose();
    _semestreCtrl.dispose();
    _rejectReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_busy) return;
    final capacidad = int.tryParse(_capacidadCtrl.text);
    final semestre = int.tryParse(_semestreCtrl.text);
    if (capacidad == null || capacidad < 1) {
      setState(() => _errorMsg = 'Capacidad debe ser un entero ≥1.');
      return;
    }
    if (semestre == null || semestre < 1 || semestre > 15) {
      setState(() => _errorMsg = 'Semestre objetivo debe estar entre 1 y 15.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(asesoriaServiceProvider).approveAsesoria(
            manager: widget.manager,
            asesoriaId: widget.asesoria.id,
            semestreObjetivo: semestre,
            capacidad: capacidad,
          );
      if (mounted) Navigator.of(context).pop();
    } on AsesoriaException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = e.message;
        });
      }
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = _rejectReasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMsg = 'Indica un motivo para rechazar.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(asesoriaServiceProvider).rejectAsesoria(
            manager: widget.manager,
            asesoriaId: widget.asesoria.id,
            reason: reason,
          );
      if (mounted) Navigator.of(context).pop();
    } on AsesoriaException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = e.message;
        });
      }
    }
  }

  Future<void> _openCv() async {
    // En web abre el PDF en una pestaña nueva. En mobile el stub no hace nada
    // (limitación conocida — si se necesita mobile, añadir url_launcher).
    await downloadFile(widget.asesoria.cvUrl, 'cv.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Solicitud: ${widget.asesoria.materia}',
          style:
              GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AdvisorLine(uid: widget.asesoria.advisorUid),
              const SizedBox(height: 12),
              _Label('Motivos del asesor'),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(40)),
                ),
                child: Text(widget.asesoria.motivos,
                    style: GoogleFonts.poppins(fontSize: 12)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Ver CV'),
                onPressed: _openCv,
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              _Label('Aprobar con estos parámetros'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _semestreCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Semestre objetivo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _capacidadCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Capacidad',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              _Label('O rechazar (motivo)'),
              const SizedBox(height: 4),
              TextField(
                controller: _rejectReasonCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Ej: CV insuficiente, materia no disponible…',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(_errorMsg!,
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, color: AppColors.error)),
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
        OutlinedButton.icon(
          icon: const Icon(Icons.close_rounded,
              color: AppColors.error, size: 18),
          label: const Text('Rechazar',
              style: TextStyle(color: AppColors.error)),
          onPressed: _busy ? null : _reject,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Aprobar'),
          onPressed: _busy ? null : _approve,
        ),
      ],
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
