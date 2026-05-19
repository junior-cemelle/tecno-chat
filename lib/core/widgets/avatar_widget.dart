import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Avatar reutilizable en toda la app.
/// Prioridad: photoUrl → iniciales del nombre → ícono genérico.
/// El color del fondo se deriva del uid para que sea siempre consistente.
class AvatarWidget extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final String uid;
  final double radius;
  final VoidCallback? onTap;

  const AvatarWidget({
    super.key,
    required this.displayName,
    required this.uid,
    this.photoUrl,
    this.radius = 22,
    this.onTap,
  });

  Color get _bgColor {
    const palette = [
      Color(0xFF1B5E9B), // azul TecNM
      Color(0xFF128C7E), // verde WhatsApp
      Color(0xFF6A1B9A), // púrpura
      Color(0xFF00695C), // teal
      Color(0xFFAD1457), // rosa
      Color(0xFF4527A0), // índigo
      Color(0xFF00838F), // cyan
      Color(0xFF558B2F), // verde olivo
    ];
    final hash = uid.codeUnits.fold(0, (a, b) => a ^ b);
    return palette[hash.abs() % palette.length];
  }

  String get _initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _buildAvatar();
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }

  Widget _buildAvatar() {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _bgColor,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (_, _s) => _InitialsAvatar(
              initials: _initials,
              color: _bgColor,
              radius: radius,
            ),
            errorWidget: (_, _s, _e) => _InitialsAvatar(
              initials: _initials,
              color: _bgColor,
              radius: radius,
            ),
          ),
        ),
      );
    }
    return _InitialsAvatar(
        initials: _initials, color: _bgColor, radius: radius);
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double radius;

  const _InitialsAvatar({
    required this.initials,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
