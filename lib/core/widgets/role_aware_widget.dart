import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

/// Muestra [child] solo si el usuario tiene el rol requerido.
/// Muestra [fallback] (o nada) si no cumple el rol.
class RoleAwareWidget extends ConsumerWidget {
  final UserRole requiredRole;
  final Widget child;
  final Widget? fallback;

  const RoleAwareWidget({
    super.key,
    required this.requiredRole,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      data: (user) {
        if (user?.role == requiredRole) return child;
        return fallback ?? const SizedBox.shrink();
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => fallback ?? const SizedBox.shrink(),
    );
  }
}

/// Versión para profesores
class TeacherOnly extends ConsumerWidget {
  final Widget child;
  final Widget? fallback;
  const TeacherOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTeacher = ref.watch(isTeacherProvider);
    return isTeacher ? child : (fallback ?? const SizedBox.shrink());
  }
}
