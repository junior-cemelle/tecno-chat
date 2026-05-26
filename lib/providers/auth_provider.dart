import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/user_model.dart';
import '../data/services/auth_service.dart';
import '../data/services/sii_api_service.dart';
import '../data/services/sii_token_storage.dart';

/// Cliente HTTP del SII. Singleton para reusar el `http.Client` interno.
final siiApiServiceProvider = Provider<SiiApiService>((ref) {
  final api = SiiApiService();
  ref.onDispose(api.dispose);
  return api;
});

/// Persistencia del JWT del SII. Debe inicializarse al arrancar la app y
/// sobreescribirse vía `ProviderScope(overrides: ...)` — Flutter requiere que
/// `SharedPreferences.getInstance()` se llame ANTES del primer `runApp`.
final siiTokenStorageProvider = Provider<SiiTokenStorage>((_) {
  throw UnimplementedError(
    'siiTokenStorageProvider debe sobreescribirse en main() antes de runApp.',
  );
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    siiApi: ref.watch(siiApiServiceProvider),
    siiTokens: ref.watch(siiTokenStorageProvider),
  );
});

/// Stream del estado de autenticación de Firebase.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Stream que reacciona a CUALQUIER cambio del usuario actual (no solo
/// login/logout). Se dispara con linkWithCredential/unlink/updateProfile,
/// así que es lo que necesitamos en la UI de "Cuentas vinculadas" para
/// refrescar tras vincular Google/Phone sin tener que hacer hot reload.
final firebaseUserChangesProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.userChanges();
});

/// Perfil Firestore del usuario autenticado actualmente.
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final userAsync = ref.watch(authStateProvider);
  // Riverpod 3: pattern matching en lugar de valueOrNull.
  final user = switch (userAsync) {
    AsyncData(:final value) => value,
    _ => null,
  };
  if (user == null) return null;
  return ref.read(authServiceProvider).getUserProfile(user.uid);
});

/// Stream en tiempo real del perfil del usuario.
final currentUserStreamProvider = StreamProvider<UserModel?>((ref) {
  final userAsync = ref.watch(authStateProvider);
  final user = switch (userAsync) {
    AsyncData(:final value) => value,
    _ => null,
  };
  if (user == null) return Stream.value(null);

  return FirebaseAuth.instance
      .userChanges()
      .asyncMap((_) async =>
          ref.read(authServiceProvider).getUserProfile(user.uid));
});

/// Conveniencia: ¿es el usuario actual un profesor?
final isTeacherProvider = Provider<bool>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final user = switch (userAsync) {
    AsyncData(:final value) => value,
    _ => null,
  };
  return user?.isTeacher ?? false;
});
