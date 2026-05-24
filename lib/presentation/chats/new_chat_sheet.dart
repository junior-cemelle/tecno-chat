import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';
import 'qr_scanner_screen_selector.dart';

/// Abre el bottom sheet para buscar un contacto e iniciar un chat.
/// Retorna el chatId si se inició una conversación, null si se canceló.
Future<String?> showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NewChatSheet(),
  );
}

class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _searchCtrl = TextEditingController();
  UserModel? _found;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _found = null;
      _error = null;
    });

    final me = await ref.read(currentUserProvider.future);
    final result = await ref.read(firestoreServiceProvider).findUser(q);

    if (!mounted) return;
    if (result == null) {
      setState(() {
        _error = 'Usuario no encontrado';
        _searching = false;
      });
    } else if (result.uid == me?.uid) {
      setState(() {
        _error = 'Ese eres tú 😉';
        _searching = false;
      });
    } else {
      setState(() {
        _found = result;
        _searching = false;
      });
    }
  }

  Future<void> _startChat(UserModel contact) async {
    final me = await ref.read(currentUserProvider.future);
    if (me == null || !mounted) return;

    // Agrega contacto si no lo tiene
    if (!me.contactIds.contains(contact.uid)) {
      await ref
          .read(firestoreServiceProvider)
          .addContact(me.uid, contact.uid);
      ref.invalidate(contactsProvider);
      ref.invalidate(currentUserProvider);
    }

    final chatId = await ref
        .read(firestoreServiceProvider)
        .getOrCreatePrivateChat(me.uid, contact.uid);

    if (mounted) Navigator.pop(context, chatId);
  }

  Future<void> _openScanner() async {
    final result = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null && mounted) {
      await _startChat(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contacts = ref.watch(contactsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ───────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(50),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Nuevo chat',
                      style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  // ── Buscador ───────────────────────────────────────
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Teléfono (+52...) o correo institucional',
                      prefixIcon:
                          const Icon(Icons.search, size: 20),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.green),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.send_rounded,
                                  size: 20, color: AppColors.primary),
                              onPressed: _search,
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 14),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 8),

                  // ── Escanear QR ────────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: Text('Escanear QR de contacto',
                        style: GoogleFonts.poppins(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ),

            // ── Resultado de búsqueda ─────────────────────────────────
            if (_found != null)
              _ContactResult(user: _found!, onTap: () => _startChat(_found!)),

            const Divider(height: 24),

            // ── Contactos existentes ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'MIS CONTACTOS',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: cs.onSurface.withAlpha(150),
                  ),
                ),
              ),
            ),
            Expanded(
              child: contacts.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.green)),
                error: (_, _) =>
                    const Center(child: Text('Error al cargar contactos')),
                data: (list) => list.isEmpty
                    ? Center(
                        child: Text(
                          'Aún no tienes contactos.\nBusca por teléfono o escanea un QR.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              color: cs.onSurface.withAlpha(120),
                              fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: list.length,
                        itemBuilder: (_, i) => _ContactResult(
                          user: list[i],
                          onTap: () => _startChat(list[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactResult extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  const _ContactResult({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: AvatarWidget(
        photoUrl: user.avatarUrl.isNotEmpty ? user.avatarUrl : null,
        displayName: user.displayName,
        uid: user.uid,
        radius: 22,
      ),
      title: Text(user.displayName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
      subtitle: Text(
        user.isTeacher
            ? 'Profesor · ${user.department ?? ''}'
            : '${user.career} · ${user.semester ?? ''}° sem.',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(fontSize: 12),
      ),
      trailing: Icon(Icons.chat_bubble_outline,
          color: Theme.of(context).colorScheme.primary, size: 18),
    );
  }
}
