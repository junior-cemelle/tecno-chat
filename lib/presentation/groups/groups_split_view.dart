import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../chats/chat_detail_screen.dart';
import 'groups_screen.dart';

/// Layout estilo WhatsApp Web para grupos: lista de grupos a la izquierda,
/// detalle a la derecha. Si no hay grupo seleccionado se muestra un panel
/// de bienvenida.
class GroupsSplitView extends ConsumerWidget {
  final String? selectedChatId;
  const GroupsSplitView({super.key, this.selectedChatId});

  static const double _listWidth = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: _listWidth,
          child: GroupsScreen(
            inSplitView: true,
            selectedChatId: selectedChatId,
          ),
        ),
        VerticalDivider(
            width: 1, thickness: 1, color: cs.onSurface.withAlpha(30)),
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

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Frosted glass background
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
                  // Transparent icon centered
                  Center(
                    child: Icon(
                      Icons.group_outlined,
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
            'Grupos',
            style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withAlpha(220)),
          ),
          const SizedBox(height: 8),
          Text(
            'Selecciona un grupo para ver la conversación',
            style: GoogleFonts.poppins(
                fontSize: 14, color: cs.onSurface.withAlpha(140)),
          ),
        ],
      ),
    );
  }
}
