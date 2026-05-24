import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/widgets/avatar_url_dialog.dart';
import '../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../core/widgets/qr_dialog.dart';
import '../../presentation/shell/app_router.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          // QR personal — para que otros puedan agregarte
          if (switch (userAsync) {
            AsyncData(value: final u) when u != null => true,
            _ => false
          })
            IconButton(
              icon: const Icon(Icons.qr_code_rounded),
              tooltip: 'Mi código QR',
              onPressed: () {
                final u = switch (userAsync) {
                  AsyncData(value: final u) when u != null => u,
                  _ => null,
                };
                if (u != null) showMyQrDialog(context, u);
              },
            ),
          // Editar perfil
          if (switch (userAsync) {
            AsyncData(value: final u) when u != null => true,
            _ => false
          })
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar perfil',
              onPressed: () => context.push('/profile/edit'),
            ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.green)),
        error: (_, e) =>
            const Center(child: Text('Error al cargar perfil')),
        data: (user) => user == null
            ? const Center(child: Text('Sin perfil'))
            : _ProfileBody(user: user, themeMode: themeMode),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final UserModel user;
  final ThemeMode themeMode;

  const _ProfileBody({required this.user, required this.themeMode});

  Future<void> _editAvatar(
      BuildContext context, WidgetRef ref, UserModel u) async {
    final newUrl = await showAvatarUrlDialog(context, u.avatarUrl, u.uid);
    if (newUrl == null) return;
    final updated = UserModel(
      uid: u.uid, phone: u.phone, email: u.email,
      displayName: u.displayName, avatarUrl: newUrl,
      role: u.role, career: u.career, semester: u.semester,
      department: u.department, isOnline: u.isOnline,
      lastSeen: u.lastSeen, contactIds: u.contactIds,
      createdAt: u.createdAt,
    );
    await ref.read(authServiceProvider).saveUserProfile(updated);
    ref.invalidate(currentUserProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final surface = cs.surface;

    return ListView(
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Container(
          color: surface,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Row(
            children: [
              AvatarWidget(
                photoUrl: user.avatarUrl.isNotEmpty ? user.avatarUrl : null,
                displayName: user.displayName,
                uid: user.uid,
                radius: 36,
                onTap: () => _editAvatar(context, ref, user),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: user.isTeacher
                            ? AppColors.primary.withAlpha(30)
                            : AppColors.green.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.isTeacher ? 'Profesor' : 'Alumno',
                        style: TextStyle(
                          color: user.isTeacher
                              ? AppColors.primary
                              : AppColors.greenDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Información académica ───────────────────────────────────────
        _Section(title: 'Información académica', tiles: [
          _InfoTile(
            icon: user.isTeacher
                ? Icons.business_outlined
                : Icons.school_outlined,
            label: user.isTeacher ? 'Departamento' : 'Carrera',
            value: user.isTeacher
                ? (user.department ?? '-')
                : user.career,
          ),
          if (!user.isTeacher && user.semester != null)
            _InfoTile(
              icon: Icons.calendar_today_outlined,
              label: 'Semestre',
              value: '${user.semester}° Semestre',
            ),
          _InfoTile(
            icon: Icons.phone_outlined,
            label: 'Teléfono',
            value: user.phone.isNotEmpty ? user.phone : 'No registrado',
          ),
        ]),
        const SizedBox(height: 8),

        // ── Ajustes ─────────────────────────────────────────────────────
        _Section(title: 'Ajustes', tiles: [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Modo oscuro'),
            value: themeMode == ThemeMode.dark,
            activeThumbColor: AppColors.green,
            onChanged: (v) => ref
                .read(themeProvider.notifier)
                .setMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notificaciones'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacidad'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ]),
        const SizedBox(height: 8),

        // ── Cerrar sesión ────────────────────────────────────────────────
        // Material es necesario para que InkWell/ListTile registre
        // eventos de mouse en Flutter web (HTML renderer).
        Material(
          color: surface,
          child: ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Cerrar sesión',
                style: TextStyle(color: AppColors.error)),
            mouseCursor: SystemMouseCursors.click,
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              // routerProvider.go() no depende de context.mounted,
              // evitando el problema de timing en web tras el signOut.
              ref.read(routerProvider).go('/login');
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _Section({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        Container(
          color: surface,
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500)),
    );
  }
}
