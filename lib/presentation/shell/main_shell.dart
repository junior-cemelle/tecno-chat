import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';

class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const MainShell({super.key, required this.shell});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _tabs = [
    _TabItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Chats'),
    _TabItem(icon: Icons.group_outlined,       activeIcon: Icons.group,        label: 'Grupos'),
    _TabItem(icon: Icons.call_outlined,        activeIcon: Icons.call,         label: 'Llamadas'),
    _TabItem(icon: Icons.person_outline,       activeIcon: Icons.person,       label: 'Perfil'),
  ];

  // IDs de llamadas ya manejadas (evita navegar dos veces por la misma)
  final _handledCallIds = <String>{};

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _cleanStaleCalls();
  }

  /// Marca como 'missed' cualquier llamada propia atascada en 'ringing'
  /// (ocurre si la app se cerró a la fuerza durante una llamada saliente).
  Future<void> _cleanStaleCalls() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('calls')
        .where('callerId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .get();
    for (final doc in snap.docs) {
      await doc.reference.update({'status': 'missed'});
    }
  }

  Future<void> _checkProfile() async {
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser == null) return; // el router redirect maneja la sesión cerrada
    // Llamada directa a Firestore para evitar caché stale de Riverpod
    final exists = await ref
        .read(authServiceProvider)
        .userProfileExists(fbUser.uid);
    if (!mounted) return;
    if (!exists) context.go('/setup');
  }

  @override
  Widget build(BuildContext context) {
    // Listener global: navega a la pantalla de llamada entrante
    ref.listen(incomingCallProvider, (_, next) {
      final call = switch (next) {
        AsyncData(value: final v) when v != null => v,
        _ => null,
      };
      if (call == null) return;
      if (_handledCallIds.contains(call.id)) return;
      _handledCallIds.add(call.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push('/incoming-call', extra: call);
      });
    });

    final userAsync = ref.watch(currentUserProvider);

    // Mientras se carga o si no hay perfil: spinner en lugar de pestañas
    final hasProfile = switch (userAsync) {
      AsyncData(value: final u) when u != null => true,
      _ => false,
    };

    if (!hasProfile) {
      return const Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.green),
        ),
      );
    }

    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell.goBranch(
          i,
          initialLocation: i == widget.shell.currentIndex,
        ),
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.activeIcon, color: AppColors.green),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem({required this.icon, required this.activeIcon, required this.label});
}
