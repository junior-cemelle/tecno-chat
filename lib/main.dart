import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'core/constants/app_assets.dart';
import 'core/platform/media_kit_init.dart';
import 'core/platform/url_strategy.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/services/sii_token_storage.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'presentation/shell/app_router.dart';

void main() async {
  configureUrlStrategy(); // URLs limpias en web (/chats en vez de /#/chats)
  WidgetsFlutterBinding.ensureInitialized();
  initMediaKit(); // no-op en web, MediaKit.ensureInitialized() en móvil
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: 'https://qxogmnglkiekrpjrulep.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4b2dtbmdsa2lla3JwanJ1bGVwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMzA4NTYsImV4cCI6MjA5NDYwNjg1Nn0.gl8I77j40lGJ6aDxnYnFrnI0jIw2GoYoeK1ja25FNbg',
  );
  await initializeDateFormatting('es');
  // SiiTokenStorage requiere inicializar SharedPreferences antes de runApp
  // (es async); por eso lo hacemos aquí y lo inyectamos vía override.
  final siiTokens = await SiiTokenStorage.create();
  runApp(ProviderScope(
    overrides: [
      siiTokenStorageProvider.overrideWithValue(siiTokens),
    ],
    child: const _Bootstrap(),
  ));
}

/// Pantalla puente que preloadea las fuentes de Google antes de mostrar la app
/// principal. Evita el flash inicial donde Poppins (y los glyphs de emoji
/// caídos al fallback del sistema) se renderizan como cuadrados con X.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = GoogleFonts.pendingFonts([
      GoogleFonts.poppins(),
      GoogleFonts.poppins(fontWeight: FontWeight.w500),
      GoogleFonts.poppins(fontWeight: FontWeight.w600),
      GoogleFonts.poppins(fontWeight: FontWeight.w700),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ready,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        return const MainApp();
      },
    );
  }
}

/// Splash mientras se descargan las fuentes (~1s en primera carga).
/// Logo lince a la izquierda, "TecNM" arriba y "Chat" abajo a la derecha.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LogoTitle(logoSize: 96, tecnmSize: 38, chatSize: 22, imageColor: Colors.white),
              const SizedBox(height: 32),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.green),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo lince + texto "TecNM" / "Chat" reutilizable en splash y sidebar.
class _LogoTitle extends StatelessWidget {
  final double logoSize;
  final double tecnmSize;
  final double chatSize;
  /// Si se indica, aplica este color sobre la imagen (útil en fondos oscuros).
  final Color? imageColor;
  const _LogoTitle({
    required this.logoSize,
    required this.tecnmSize,
    required this.chatSize,
    this.imageColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          AppAssets.logoLince,
          height: logoSize,
          color: imageColor,
          colorBlendMode: imageColor != null ? BlendMode.srcIn : null,
          errorBuilder: (ctx, err, st) => Icon(
              Icons.school_rounded,
              color: imageColor ?? AppColors.primary,
              size: logoSize),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TecNM',
              style: TextStyle(
                color: Colors.white,
                fontSize: tecnmSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Chat',
              style: TextStyle(
                color: Colors.white.withAlpha(140),
                fontSize: chatSize,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'TecNM Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
