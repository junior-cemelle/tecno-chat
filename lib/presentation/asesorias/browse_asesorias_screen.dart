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

/// Pantalla de búsqueda de asesorías para el alumno consultante.
/// - Filtro por materia (texto libre, case-insensitive)
/// - Solo muestra asesorías aprobadas con cupo
/// - El estado del CTA cambia según la relación del alumno con la asesoría
class BrowseAsesoriasScreen extends ConsumerStatefulWidget {
  const BrowseAsesoriasScreen({super.key});

  @override
  ConsumerState<BrowseAsesoriasScreen> createState() =>
      _BrowseAsesoriasScreenState();
}

class _BrowseAsesoriasScreenState extends ConsumerState<BrowseAsesoriasScreen> {
  final _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar asesorías')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, _) =>
            const Center(child: Text('Error cargando perfil')),
        data: (user) {
          if (user == null) return const SizedBox.shrink();
          if (!user.isStudent) {
            return const Center(
                child: Text('Solo alumnos pueden buscar asesorías.'));
          }
          return _Body(student: user, filter: _filter, onFilter: (q) {
            setState(() => _filter = q.trim().toLowerCase());
          }, searchCtrl: _searchCtrl);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final UserModel student;
  final String filter;
  final ValueChanged<String> onFilter;
  final TextEditingController searchCtrl;

  const _Body({
    required this.student,
    required this.filter,
    required this.onFilter,
    required this.searchCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asesoriasAsync = ref.watch(approvedAsesoriasProvider);
    final myRequestsAsync = ref.watch(requestsByStudentProvider(student.uid));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: searchCtrl,
                onChanged: onFilter,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Filtrar por materia…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                  suffixIcon: filter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            searchCtrl.clear();
                            onFilter('');
                          },
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: asesoriasAsync.when(
                loading: () => const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.green)),
                error: (e, _) =>
                    Center(child: Text('Error al cargar: $e')),
                data: (asesorias) {
                  // Filtros client-side: por materia (text) + excluyendo
                  // asesorías propias del estudiante (no puede inscribirse en
                  // sí mismo).
                  final filtered = asesorias.where((a) {
                    if (a.advisorUid == student.uid) return false;
                    if (filter.isEmpty) return true;
                    return a.materia.toLowerCase().contains(filter);
                  }).toList();

                  if (filtered.isEmpty) {
                    return _empty(
                      context,
                      icon: Icons.search_off_outlined,
                      text: filter.isEmpty
                          ? 'No hay asesorías disponibles en este momento.'
                          : 'No hay asesorías de "${searchCtrl.text}".',
                    );
                  }

                  final myRequestsByAsesoria =
                      <String, AsesoriaRequest>{};
                  for (final r in (myRequestsAsync.value ?? [])) {
                    // Solo nos importa la última solicitud por asesoría
                    // (asumimos: solo puede haber una pending; si la rechazaron
                    // se puede volver a solicitar — pero la UI mostrará la
                    // más reciente que es la decisión vigente).
                    final prev = myRequestsByAsesoria[r.asesoriaId];
                    if (prev == null ||
                        r.createdAt.isAfter(prev.createdAt)) {
                      myRequestsByAsesoria[r.asesoriaId] = r;
                    }
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final a = filtered[i];
                      return _AsesoriaCard(
                        asesoria: a,
                        student: student,
                        myRequest: myRequestsByAsesoria[a.id],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context,
      {required IconData icon, required String text}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: cs.onSurface.withAlpha(110)),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: cs.onSurface.withAlpha(170))),
          ],
        ),
      ),
    );
  }
}

// ── Card de una asesoría ────────────────────────────────────────────────────

class _AsesoriaCard extends ConsumerWidget {
  final Asesoria asesoria;
  final UserModel student;
  final AsesoriaRequest? myRequest;

  const _AsesoriaCard({
    required this.asesoria,
    required this.student,
    required this.myRequest,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isMember = asesoria.studentUids.contains(student.uid);
    final isFull = asesoria.estaLlena;
    final isPendingMine =
        myRequest?.status == AsesoriaRequestStatus.pending;
    final isRejectedMine =
        myRequest?.status == AsesoriaRequestStatus.rejected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withAlpha(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asesoria.materia,
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    _AdvisorLine(uid: asesoria.advisorUid),
                  ],
                ),
              ),
              _CupoBadge(
                disponibles: asesoria.cuposDisponibles,
                capacidad: asesoria.capacidad,
                isFull: isFull,
              ),
            ],
          ),
          if (asesoria.motivos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              asesoria.motivos,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, color: cs.onSurface.withAlpha(170)),
            ),
          ],
          const SizedBox(height: 10),
          // CTA
          Align(
            alignment: Alignment.centerRight,
            child: _ctaFor(
              context: context,
              ref: ref,
              isMember: isMember,
              isFull: isFull,
              isPendingMine: isPendingMine,
              isRejectedMine: isRejectedMine,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctaFor({
    required BuildContext context,
    required WidgetRef ref,
    required bool isMember,
    required bool isFull,
    required bool isPendingMine,
    required bool isRejectedMine,
  }) {
    if (isMember) {
      return FilledButton.icon(
        icon: const Icon(Icons.chat_bubble_outline, size: 16),
        label: const Text('Ir al chat'),
        onPressed: asesoria.chatId == null
            ? null
            // Salta al branch específico de chats de asesoría
            // (en lugar de /chats genérico) para que aparezca seleccionado
            // en su propia sección del sidebar.
            : () => context.go('/asesoria-chats/${asesoria.chatId}'),
      );
    }
    if (isPendingMine) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.hourglass_top_rounded, size: 16),
        label: const Text('Solicitud enviada'),
        onPressed: null,
      );
    }
    if (isFull) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.group_off_outlined, size: 16),
        label: const Text('Llena'),
        onPressed: null,
      );
    }
    // Si fue rechazada antes, permitimos volver a solicitar
    final label =
        isRejectedMine ? 'Volver a solicitar' : 'Solicitar asesoría';
    return FilledButton.icon(
      icon: const Icon(Icons.send_rounded, size: 16),
      label: Text(label),
      onPressed: () => _openRequestDialog(context, ref),
    );
  }

  Future<void> _openRequestDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RequestDialog(asesoria: asesoria, student: student),
    );
  }
}

class _CupoBadge extends StatelessWidget {
  final int? disponibles;
  final int? capacidad;
  final bool isFull;
  const _CupoBadge(
      {required this.disponibles,
      required this.capacidad,
      required this.isFull});

  @override
  Widget build(BuildContext context) {
    if (disponibles == null || capacidad == null) {
      return const SizedBox.shrink();
    }
    final color = isFull
        ? AppColors.error
        : (disponibles! <= 1 ? Colors.orange.shade700 : AppColors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$disponibles/$capacidad cupos',
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// FutureProvider local que cachea el lookup de asesores mientras viva la
// pantalla. Igual que en el dashboard del gerente.
final _advisorUserProvider =
    FutureProvider.family<UserModel?, String>((ref, uid) {
  return ref.read(asesoriaServiceProvider).getUser(uid);
});

class _AdvisorLine extends ConsumerWidget {
  final String uid;
  const _AdvisorLine({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futureUser = ref.watch(_advisorUserProvider(uid));
    return futureUser.when(
      loading: () => Text('Cargando asesor…',
          style: GoogleFonts.poppins(
              fontSize: 11.5, color: Colors.grey.shade400)),
      error: (_, _) =>
          Text('Asesor: $uid', style: GoogleFonts.poppins(fontSize: 11.5)),
      data: (u) => Text(
        u == null
            ? 'Asesor desconocido'
            : '${u.displayName} · ${u.semester ?? '?'}º sem',
        style: GoogleFonts.poppins(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(180)),
      ),
    );
  }
}

// ── Dialog de solicitud ────────────────────────────────────────────────────

class _RequestDialog extends ConsumerStatefulWidget {
  final Asesoria asesoria;
  final UserModel student;
  const _RequestDialog({required this.asesoria, required this.student});

  @override
  ConsumerState<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends ConsumerState<_RequestDialog> {
  final _msgCtrl = TextEditingController();
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(asesoriaServiceProvider).requestToJoin(
            student: widget.student,
            asesoriaId: widget.asesoria.id,
            mensaje: _msgCtrl.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Solicitud enviada. El asesor la revisará pronto.'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } on AsesoriaException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Solicitar: ${widget.asesoria.materia}',
          style:
              GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'El asesor decidirá si te acepta. Puedes dejarle un mensaje '
              'opcional explicando por qué te interesa la asesoría.',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _msgCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Mensaje (opcional)',
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
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Enviar'),
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
