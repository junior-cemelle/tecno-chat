import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/call_model.dart';
import '../../providers/call_provider.dart';
import '../../providers/firestore_provider.dart';

class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final historyAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Llamadas',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: historyAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, _) => const Center(child: Text('Error al cargar historial')),
        data: (calls) => calls.isEmpty
            ? _EmptyState()
            : ListView.separated(
                itemCount: calls.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) =>
                    _CallTile(call: calls[i], myUid: myUid),
              ),
      ),
    );
  }
}

class _CallTile extends ConsumerWidget {
  final CallModel call;
  final String myUid;
  const _CallTile({required this.call, required this.myUid});

  bool get _isCaller => call.callerId == myUid;
  String get _otherUid => _isCaller ? call.receiverId : call.callerId;

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return DateFormat('HH:mm').format(dt);
    }
    if (now.difference(dt).inDays < 7) {
      return DateFormat('E', 'es').format(dt);
    }
    return DateFormat('dd/MM/yy').format(dt);
  }

  String _durationLabel() {
    final s = call.durationSecs;
    if (s == null || s == 0) return '';
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${s % 60}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(_otherUid));
    final name = switch (userAsync) {
      AsyncData(value: final u) when u != null => u.displayName,
      _ => 'Usuario',
    };
    final photo = switch (userAsync) {
      AsyncData(value: final u) when u != null && u.avatarUrl.isNotEmpty =>
        u.avatarUrl,
      _ => null,
    };

    final (icon, color) = switch (call.status) {
      CallStatus.rejected => (Icons.call_missed_outgoing, AppColors.error),
      CallStatus.missed => (Icons.call_missed, AppColors.error),
      _ => _isCaller
          ? (Icons.call_made, AppColors.green)
          : (Icons.call_received, AppColors.primary),
    };

    final durLabel = _durationLabel();
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AvatarWidget(
          photoUrl: photo, displayName: name, uid: _otherUid, radius: 24),
      title: Text(name,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            call.type == CallType.video ? 'Videollamada' : 'Llamada de voz',
            style: GoogleFonts.poppins(
                fontSize: 12, color: cs.onSurface.withAlpha(140)),
          ),
          if (durLabel.isNotEmpty) ...[
            Text(' · ',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: cs.onSurface.withAlpha(100))),
            Text(durLabel,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: cs.onSurface.withAlpha(120))),
          ],
        ],
      ),
      trailing: Text(
        _formatTime(call.startedAt),
        style: GoogleFonts.poppins(
            fontSize: 11, color: cs.onSurface.withAlpha(120)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_outlined,
              size: 80, color: cs.onSurface.withAlpha(60)),
          const SizedBox(height: 16),
          Text('Sin historial de llamadas',
              style: GoogleFonts.poppins(
                  fontSize: 16, color: cs.onSurface.withAlpha(160))),
        ],
      ),
    );
  }
}
