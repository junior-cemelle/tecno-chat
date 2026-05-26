import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/login_screen.dart';
import '../auth/otp_screen.dart';
import '../auth/profile_setup_screen.dart';
import '../calls/call_screen.dart';
import '../calls/incoming_call_screen.dart';
import '../calls/calls_screen.dart';
import '../chats/chats_screen.dart';
import '../chats/chats_split_view.dart';
import '../chats/chat_detail_screen.dart';
import '../groups/groups_screen.dart';
import '../groups/groups_split_view.dart';
import '../groups/create_group_screen.dart';
import '../groups/group_info_screen.dart';
import '../stories/create_story_screen.dart';
import '../asesorias/apply_advisor_screen.dart';
import '../asesorias/asesoria_chats_screen.dart';
import '../asesorias/asesoria_chats_split_view.dart';
import '../asesorias/browse_asesorias_screen.dart';
import '../asesorias/manager_dashboard_screen.dart';
import '../asesorias/my_asesorias_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../sii/sii_calificaciones_screen.dart';
import '../sii/sii_dashboard_screen.dart';
import '../sii/sii_horarios_screen.dart';
import '../sii/sii_kardex_screen.dart';
import 'main_shell.dart';

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier();
  // Ubicación inicial según sesión activa al arrancar la app
  final initialUser = FirebaseAuth.instance.currentUser;

  return GoRouter(
    initialLocation: initialUser == null ? '/login' : '/chats',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn = FirebaseAuth.instance.currentUser != null;
      final path = state.uri.path;

      // Sin sesión: solo se permite login y otp
      if (!loggedIn && path != '/login' && path != '/otp') return '/login';

      // Con sesión activa y aún en /login u /otp: salir hacia /chats.
      // EXCEPCIÓN: /otp en linkMode es para vincular teléfono post-registro,
      // ahí el usuario está logueado por diseño y NO debe redirigirse.
      if (loggedIn && (path == '/login' || path == '/otp')) {
        if (path == '/otp') {
          final extra = state.extra;
          if (extra is Map && extra['linkMode'] == true) return null;
        }
        return '/chats';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final extra = Map<String, dynamic>.from(state.extra as Map);
          return OtpScreen(
            verificationId: extra['verificationId'] as String,
            phone: extra['phone'] as String,
            linkMode: extra['linkMode'] as bool? ?? false,
            returnTo: extra['returnTo'] as String? ?? '/profile',
          );
        },
      ),
      // /setup tiene transición de fade para no parecer popup
      GoRoute(
        path: '/setup',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ProfileSetupScreen(),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      // Crear grupo (solo profesores, fuera del shell para pantalla completa)
      GoRoute(
        path: '/create-group',
        builder: (_, _) => const CreateGroupScreen(),
      ),
      // Info/ajustes de un grupo
      GoRoute(
        path: '/group-info/:chatId',
        builder: (_, state) => GroupInfoScreen(
          chatId: state.pathParameters['chatId']!,
        ),
      ),
      // Crear story/aviso institucional (solo profesores)
      GoRoute(
        path: '/create-story',
        builder: (_, _) => const CreateStoryScreen(),
      ),
      // Asesorías: alumno solicita ser asesor
      GoRoute(
        path: '/asesorias/apply',
        builder: (_, _) => const ApplyAdvisorScreen(),
      ),
      // Asesorías: alumno busca asesorías disponibles
      GoRoute(
        path: '/asesorias/browse',
        builder: (_, _) => const BrowseAsesoriasScreen(),
      ),
      // Asesorías: vista del asesor (mis asesorías + solicitudes entrantes)
      GoRoute(
        path: '/asesorias/mine',
        builder: (_, _) => const MyAsesoriasScreen(),
      ),
      // Asesorías: dashboard del gerente
      GoRoute(
        path: '/asesorias/manage',
        builder: (_, _) => const ManagerDashboardScreen(),
      ),
      // Pantalla de llamada activa (voz o video)
      GoRoute(
        path: '/call',
        builder: (_, state) {
          final extra = Map<String, dynamic>.from(state.extra as Map);
          return CallScreen(
            callId: extra['callId'] as String,
            channelId: extra['channelId'] as String,
            isVideo: extra['isVideo'] as bool,
            isCaller: extra['isCaller'] as bool,
            remoteUid: extra['remoteUid'] as String,
          );
        },
      ),
      // Pantalla de llamada entrante
      GoRoute(
        path: '/incoming-call',
        builder: (_, state) => IncomingCallScreen(
          call: state.extra as dynamic,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/chats',
              // En web: split view (lista + detalle); en móvil: lista normal.
              builder: (_, _) => kIsWeb
                  ? const ChatsSplitView()
                  : const ChatsScreen(),
              routes: [
                GoRoute(
                  path: ':chatId',
                  // En web: mismo ChatsSplitView con el chat seleccionado.
                  // En móvil: empuja la pantalla de detalle a pantalla completa.
                  builder: (_, state) {
                    final id = state.pathParameters['chatId']!;
                    return kIsWeb
                        ? ChatsSplitView(selectedChatId: id)
                        : ChatDetailScreen(chatId: id);
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/groups',
              // En web: split view (lista + detalle); en móvil: lista normal.
              builder: (_, _) => kIsWeb
                  ? const GroupsSplitView()
                  : const GroupsScreen(),
              routes: [
                GoRoute(
                  path: ':chatId',
                  // En web: mismo GroupsSplitView con el grupo seleccionado.
                  // En móvil: detalle a pantalla completa (mismo widget que chats).
                  builder: (_, state) {
                    final id = state.pathParameters['chatId']!;
                    return kIsWeb
                        ? GroupsSplitView(selectedChatId: id)
                        : ChatDetailScreen(chatId: id);
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/calls', builder: (_, _) => const CallsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (_, _) => const EditProfileScreen(),
                ),
              ],
            ),
          ]),
          // ── Branches SII (solo se exponen en sidebar para alumnos) ──────
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/sii/dashboard',
              builder: (_, _) => const SiiDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/sii/calificaciones',
              builder: (_, _) => const SiiCalificacionesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/sii/kardex',
              builder: (_, _) => const SiiKardexScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/sii/horarios',
              builder: (_, _) => const SiiHorariosScreen(),
            ),
          ]),
          // ── Branch 8: chats de asesoría ─────────────────────────────────
          // En web split view (lista + detalle), en móvil lista normal y el
          // detalle se empuja como pantalla completa reutilizando ChatDetailScreen.
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/asesoria-chats',
              builder: (_, _) => kIsWeb
                  ? const AsesoriaChatsSplitView()
                  : const AsesoriaChatsScreen(),
              routes: [
                GoRoute(
                  path: ':chatId',
                  builder: (_, state) {
                    final id = state.pathParameters['chatId']!;
                    return kIsWeb
                        ? AsesoriaChatsSplitView(selectedChatId: id)
                        : ChatDetailScreen(chatId: id);
                  },
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
