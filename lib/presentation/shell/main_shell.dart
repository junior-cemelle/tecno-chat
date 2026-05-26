import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_assets.dart';
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
  // Las branches del router están en este orden:
  //   0:Chats 1:Grupos 2:Llamadas 3:Perfil
  //   4:Dashboard 5:Calif 6:Kardex 7:Horarios 8:Asesorías-chats
  // El sidebar reordena (Asesorías entre Grupos y Llamadas; Perfil al final).
  static const _commonTabs = [
    _TabItem(
      branchIndex: 0,
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      label: 'Chats',
    ),
    _TabItem(
      branchIndex: 1,
      icon: Icons.group_outlined,
      activeIcon: Icons.group,
      label: 'Grupos',
    ),
    _TabItem(
      branchIndex: 8,
      icon: Icons.school_outlined,
      activeIcon: Icons.school,
      label: 'Asesorías',
    ),
    _TabItem(
      branchIndex: 2,
      icon: Icons.call_outlined,
      activeIcon: Icons.call,
      label: 'Llamadas',
    ),
  ];

  static const _studentSiiTabs = [
    _TabItem(
      branchIndex: 4,
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Sobre mí',
      dividerBefore: true,
    ),
    _TabItem(
      branchIndex: 5,
      icon: Icons.grading_outlined,
      activeIcon: Icons.grading,
      label: 'Calificaciones',
    ),
    _TabItem(
      branchIndex: 6,
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book,
      label: 'Kárdex',
    ),
    _TabItem(
      branchIndex: 7,
      icon: Icons.calendar_view_week_outlined,
      activeIcon: Icons.calendar_view_week,
      label: 'Horarios',
    ),
  ];

  static const _profileTab = _TabItem(
    branchIndex: 3,
    icon: Icons.person_outline,
    activeIcon: Icons.person,
    label: 'Perfil',
    dividerBefore: true,
  );

  List<_TabItem> _visibleTabs(bool isStudent) => [
        ..._commonTabs,
        if (isStudent) ..._studentSiiTabs,
        _profileTab,
      ];

  // Ancho del sidebar
  static const double _expandedWidth = 220;
  static const double _collapsedWidth = 60;

  final _handledCallIds = <String>{};
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _cleanStaleCalls();
  }

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
    if (fbUser == null) return;

    // Retry con backoff porque el redirect a /chats puede dispararse en cuanto
    // `createUserWithEmailAndPassword` cambia el authState — ANTES de que
    // `_createStudentProfileFromSii` termine de escribir el doc en Firestore.
    // Sin retry, este check vería `exists=false` por ~200-500ms y mandaría
    // al alumno recién creado a /setup en vez de a /chats.
    const delaysMs = [0, 250, 500, 750, 1000, 1500];
    for (final delay in delaysMs) {
      if (delay > 0) await Future.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      final exists = await ref
          .read(authServiceProvider)
          .userProfileExists(fbUser.uid);
      if (exists) {
        // El FutureProvider ya pudo haber cacheado `null` (porque corrió antes
        // de que _createStudentProfileFromSii terminara de escribir el doc).
        // Lo invalidamos para que vuelva a leer Firestore y el shell salga
        // del CircularProgressIndicator.
        ref.invalidate(currentUserProvider);
        return;
      }
    }

    if (!mounted) return;
    context.go('/setup');
  }

  @override
  Widget build(BuildContext context) {
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

    return userAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(child: CircularProgressIndicator(color: AppColors.green)),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 60, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  'Error cargando tu perfil. Intenta reiniciar la app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(currentUserProvider);
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (user) {
        if (user == null) {
          return const Scaffold(
            backgroundColor: AppColors.darkBg,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.green),
            ),
          );
        }
        final tabs = _visibleTabs(user.isStudent);
        return kIsWeb
            ? _buildWebLayout(tabs)
            : _buildMobileLayout(tabs);
      },
    );
  }

  /// Encuentra el índice visual del tab cuya branch coincide con la activa.
  /// Si la branch actual no es visible (caso raro: profesor en branch SII),
  /// devuelve 0 para no romper el NavigationBar.
  int _visualIndexForBranch(List<_TabItem> tabs, int branchIndex) {
    final i = tabs.indexWhere((t) => t.branchIndex == branchIndex);
    return i < 0 ? 0 : i;
  }

  // ── Móvil: BottomNavigationBar ─────────────────────────────────────────────

  Widget _buildMobileLayout(List<_TabItem> tabs) {
    final selected = _visualIndexForBranch(tabs, widget.shell.currentIndex);
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) {
          final branch = tabs[i].branchIndex;
          widget.shell.goBranch(
            branch,
            initialLocation: branch == widget.shell.currentIndex,
          );
        },
        destinations: tabs
            .map(
              (t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon, color: AppColors.green),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Web: Sidebar de glassmorphism colapsable ───────────────────────────────

  Widget _buildWebLayout(List<_TabItem> tabs) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarWidth = _sidebarCollapsed ? _collapsedWidth : _expandedWidth;
    final selected = _visualIndexForBranch(tabs, widget.shell.currentIndex);

    return Scaffold(
      body: Stack(
        children: [
          // ── Capa 0: degradado decorativo que se ve a través del sidebar ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF1B2840), Color(0xFF0F1B2E)]
                      : [
                          AppColors.primary.withAlpha(60),
                          AppColors.green.withAlpha(40),
                        ],
                ),
              ),
            ),
          ),

          // ── Capa 1: contenido principal (a la derecha del sidebar) ──────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            left: sidebarWidth,
            right: 0,
            top: 0,
            bottom: 0,
            child: ColoredBox(color: cs.surface, child: widget.shell),
          ),

          // ── Capa 2: sidebar de glassmorphism ────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            left: 0,
            top: 0,
            bottom: 0,
            width: sidebarWidth,
            child: _GlassSidebar(
              collapsed: _sidebarCollapsed,
              tabs: tabs,
              currentIndex: selected,
              onTabSelected: (i) {
                final branch = tabs[i].branchIndex;
                widget.shell.goBranch(
                  branch,
                  initialLocation: branch == widget.shell.currentIndex,
                );
              },
              onToggle: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar con glassmorphism ─────────────────────────────────────────────────

class _GlassSidebar extends StatelessWidget {
  final bool collapsed;
  final List<_TabItem> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onToggle;
  final bool isDark;

  const _GlassSidebar({
    required this.collapsed,
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // BackdropFilter desenfoca el degradado de la capa 0 detrás del sidebar
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [Colors.white.withAlpha(28), Colors.white.withAlpha(10)]
                  : [Colors.white.withAlpha(180), Colors.white.withAlpha(120)],
            ),
            border: Border(
              right: BorderSide(
                color: Colors.white.withAlpha(isDark ? 50 : 110),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cabecera: logo (botón de colapsar) ────────────────────
              _SidebarHeader(collapsed: collapsed, onToggle: onToggle),

              Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.white.withAlpha(isDark ? 40 : 90),
              ),
              const SizedBox(height: 8),

              // ── Items de navegación ───────────────────────────────────
              // `dividerBefore` agrega una línea + espacio antes del item
              // (excepto si es el primero, donde no tiene sentido). Lo usan
              // los tabs SII y Perfil para crear secciones visuales.
              for (int i = 0; i < tabs.length; i++) ...[
                if (i > 0 && tabs[i].dividerBefore) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: collapsed ? 10 : 16),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withAlpha(isDark ? 40 : 90),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _SidebarItem(
                  icon: i == currentIndex
                      ? tabs[i].activeIcon
                      : tabs[i].icon,
                  label: tabs[i].label,
                  selected: i == currentIndex,
                  collapsed: collapsed,
                  onTap: () => onTabSelected(i),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cabecera del sidebar (logo + botón colapsar) ──────────────────────────────

class _SidebarHeader extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggle;

  const _SidebarHeader({required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Expandir menú' : 'Colapsar menú',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          child: SizedBox(
            // Altura fija evita propagación de altura infinita; el Row se
            // limita a este alto sin importar el ancho actual del sidebar.
            height: 70,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showLabels = constraints.maxWidth >= 140;
                final horizontalPadding =
                    collapsed || constraints.maxWidth < 140 ? 10.0 : 16.0;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed || !showLabels
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      Image.asset(
                        AppAssets.logoLince,
                        height: 40,
                        errorBuilder: (ctx, err, st) => const Icon(
                          Icons.school_rounded,
                          color: Color.fromARGB(255, 255, 255, 255),
                          size: 40,
                        ),
                      ),
                      if (showLabels) ...[
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TecNM',
                                overflow: TextOverflow.clip,
                                softWrap: false,
                                maxLines: 1,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color.fromARGB(
                                    255,
                                    255,
                                    255,
                                    255,
                                  ),
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Chat',
                                overflow: TextOverflow.clip,
                                softWrap: false,
                                maxLines: 1,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color.fromARGB(
                                    255,
                                    206,
                                    206,
                                    206,
                                  ).withAlpha(140),
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Item de navegación del sidebar ────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? AppColors.green : cs.onSurface.withAlpha(180);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 6 : 10,
        vertical: 0,
      ),
      child: Material(
        color: selected ? AppColors.green.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Tooltip(
            message: collapsed ? label : '',
            child: SizedBox(
              // Altura fija: evita propagar la altura infinita del Column padre.
              height: 48,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showLabel = !collapsed && constraints.maxWidth >= 120;
                  final horizontalPadding = showLabel ? 3.0 : 0.0;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Row(
                      mainAxisAlignment: showLabel
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: color, size: 22),
                        if (showLabel) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              maxLines: 1,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tab descriptor ────────────────────────────────────────────────────────────

class _TabItem {
  /// Índice de la branch en `StatefulShellRoute.indexedStack`. Es distinto del
  /// índice visual del tab porque el sidebar reordena (Perfil al final) y
  /// oculta los tabs SII para profesores.
  final int branchIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  /// Si true, el sidebar dibuja un separador (línea + espacio) encima.
  /// Solo aplica al sidebar web — el `NavigationBar` móvil lo ignora.
  final bool dividerBefore;
  const _TabItem({
    required this.branchIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.dividerBefore = false,
  });
}
