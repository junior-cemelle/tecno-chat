import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/user_model.dart';
import '../data/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((_) => AuthService());

/// Stream del estado de autenticación de Firebase.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
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
