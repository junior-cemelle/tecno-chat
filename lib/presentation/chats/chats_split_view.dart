import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'chat_detail_screen.dart';
import 'chats_screen.dart';

/// Layout estilo WhatsApp Web: lista de chats a la izquierda, detalle a la
/// derecha. Cuando no hay chat seleccionado se muestra un panel de bienvenida.
class ChatsSplitView extends ConsumerWidget {
  final String? selectedChatId;
  const ChatsSplitView({super.key, this.selectedChatId});

  /// Ancho fijo del panel de chats (similar a WhatsApp Web).
  static const double _listWidth = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        // ── Panel izquierdo: lista de chats ────────────────────────────────
        SizedBox(
          width: _listWidth,
          child: ChatsScreen(
            inSplitView: true,
            selectedChatId: selectedChatId,
          ),
        ),
        VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.onSurface.withAlpha(30)),
        // ── Panel derecho: detalle del chat o bienvenida ───────────────────
        Expanded(
          child: selectedChatId == null
              ? const _WelcomePanel()
              : ChatDetailScreen(
                  key: ValueKey(selectedChatId),
                  chatId: selectedChatId!,
                  inSplitView: true,
                ),
        ),
      ],
    );
  }
}

// ── Panel de bienvenida cuando no hay chat seleccionado ───────────────────────

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono glassmorphism: degradado sutil + borde blanco + icono semitransparente
          SizedBox(
            width: 120,
            height: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withAlpha(30),
                            Colors.white.withAlpha(10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withAlpha(64),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 56,
                      color: Colors.white.withAlpha(72),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Chats',
            style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withAlpha(220)),
          ),
          const SizedBox(height: 8),
          Text(
            'Selecciona una conversación para comenzar',
            style: GoogleFonts.poppins(
                fontSize: 14, color: cs.onSurface.withAlpha(140)),
          ),
        ],
      ),
    );
  }
}
