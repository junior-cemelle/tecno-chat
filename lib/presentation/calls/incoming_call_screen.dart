import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/call_model.dart';
import '../../providers/call_provider.dart';
import '../../providers/firestore_provider.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final CallModel call;
  const IncomingCallScreen({super.key, required this.call});

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  StreamSubscription<CallModel?>? _sub;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // Si el llamante cancela antes de que el receptor responda, cerrar automáticamente
    _sub = ref
        .read(callServiceProvider)
        .watchCall(widget.call.id)
        .listen((call) {
      if (_handled || call == null) return;
      if (call.status != CallStatus.ringing && mounted) {
        _handled = true;
        context.pop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_handled) return;
    _handled = true;
    await ref
        .read(callServiceProvider)
        .updateStatus(widget.call.id, CallStatus.accepted);
    if (mounted) {
      context.pushReplacement('/call', extra: {
        'callId': widget.call.id,
        'channelId': widget.call.channelId,
        'isVideo': widget.call.type == CallType.video,
        'isCaller': false,
        'remoteUid': widget.call.callerId,
      });
    }
  }

  Future<void> _reject() async {
    if (_handled) return;
    _handled = true;
    await ref
        .read(callServiceProvider)
        .updateStatus(widget.call.id, CallStatus.rejected);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final callerAsync = ref.watch(userProfileProvider(widget.call.callerId));
    final callerName = switch (callerAsync) {
      AsyncData(value: final u) when u != null => u.displayName,
      _ => 'Llamada entrante',
    };
    final callerPhoto = switch (callerAsync) {
      AsyncData(value: final u) when u != null && u.avatarUrl.isNotEmpty =>
        u.avatarUrl,
      _ => null,
    };
    final isVideo = widget.call.type == CallType.video;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            AvatarWidget(
              photoUrl: callerPhoto,
              displayName: callerName,
              uid: widget.call.callerId,
              radius: 56,
            ),
            const SizedBox(height: 20),
            Text(
              callerName,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVideo ? 'Videollamada entrante' : 'Llamada de voz entrante',
              style: GoogleFonts.poppins(
                color: Colors.white.withAlpha(180),
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Padding(
              padding:
                  const EdgeInsets.only(bottom: 56, left: 64, right: 64),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ActionBtn(
                    icon: Icons.call_end,
                    color: AppColors.error,
                    label: 'Rechazar',
                    onTap: _reject,
                  ),
                  _ActionBtn(
                    icon: isVideo ? Icons.videocam : Icons.call,
                    color: AppColors.green,
                    label: 'Aceptar',
                    onTap: _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}
