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
  static const _tabs = [
    _TabItem(
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      label: 'Chats',
    ),
    _TabItem(
      icon: Icons.group_outlined,
      activeIcon: Icons.group,
      label: 'Grupos',
    ),
    _TabItem(
      icon: Icons.call_outlined,
      activeIcon: Icons.call,
      label: 'Llamadas',
    ),
    _TabItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Perfil',
    ),
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
    final exists = await ref
        .read(authServiceProvider)
        .userProfileExists(fbUser.uid);
    if (!mounted) return;
    if (!exists) context.go('/setup');
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
    final hasProfile = switch (userAsync) {
      AsyncData(value: final u) when u != null => true,
      _ => false,
    };

    if (!hasProfile) {
      return const Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(child: CircularProgressIndicator(color: AppColors.green)),
      );
    }

    return kIsWeb ? _buildWebLayout() : _buildMobileLayout();
  }

  // ── Móvil: BottomNavigationBar ─────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell.goBranch(
          i,
          initialLocation: i == widget.shell.currentIndex,
        ),
        destinations: _tabs
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

  Widget _buildWebLayout() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarWidth = _sidebarCollapsed ? _collapsedWidth : _expandedWidth;

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
              tabs: _tabs,
              currentIndex: widget.shell.currentIndex,
              onTabSelected: (i) => widget.shell.goBranch(
                i,
                initialLocation: i == widget.shell.currentIndex,
              ),
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
              ...List.generate(tabs.length, (i) {
                final tab = tabs[i];
                final selected = i == currentIndex;
                return _SidebarItem(
                  icon: selected ? tab.activeIcon : tab.icon,
                  label: tab.label,
                  selected: selected,
                  collapsed: collapsed,
                  onTap: () => onTabSelected(i),
                );
              }),
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
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
