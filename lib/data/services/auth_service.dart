import 'dart:convert' show base64;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/sii_models.dart';
import '../models/user_model.dart';
import 'sii_api_service.dart';
import 'sii_token_storage.dart';
import 'storage_service.dart';

/// Error de auth pensado para mostrarse al usuario directamente.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final SiiApiService _siiApi;
  final SiiTokenStorage _siiTokens;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    required SiiApiService siiApi,
    required SiiTokenStorage siiTokens,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _siiApi = siiApi,
        _siiTokens = siiTokens;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Phone (vinculación post-registro y login si ya está vinculado) ────────

  /// Envía OTP al número dado. Llama [onCodeSent] con el verificationId.
  /// El flujo de phone YA NO crea perfiles nuevos — solo loguea si el teléfono
  /// está vinculado a un usuario existente (ver [signInWithOtpForLogin]).
  Future<void> verifyPhone({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential)? onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        onAutoVerified?.call(credential);
      },
      verificationFailed: (e) => onError(e.message ?? 'Error de verificación'),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Login vía OTP. Si el teléfono no está vinculado a ningún usuario con
  /// perfil registrado, deshace el sign-in y lanza [AuthException] para evitar
  /// "registros fantasma" (alumnos/profesores deben registrarse por email
  /// primero; el teléfono solo sirve para login post-vinculación).
  Future<UserCredential> signInWithOtpForLogin(
      String verificationId, String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final cred = await _auth.signInWithCredential(credential);
    final uid = cred.user?.uid;
    if (uid == null) {
      throw const AuthException('No se obtuvo UID');
    }

    final exists = await userProfileExists(uid);
    if (!exists) {
      // Phone-auth creó un usuario Firebase sin perfil → lo limpiamos.
      try {
        await cred.user?.delete();
      } catch (_) {
        await _auth.signOut();
      }
      throw const AuthException(
        'Este teléfono no está vinculado a ninguna cuenta. '
        'Inicia sesión con tu correo institucional primero y luego vincula tu teléfono.',
      );
    }
    return cred;
  }

  /// Vincula un PhoneAuthCredential al usuario actualmente autenticado.
  /// Solo aplicable post-registro.
  Future<void> linkPhoneCredential(PhoneAuthCredential phoneCredential) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('No hay usuario activo');
    try {
      final result = await user.linkWithCredential(phoneCredential);
      final phone = result.user?.phoneNumber ?? user.phoneNumber ?? '';
      if (phone.isNotEmpty) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .update({'phone': phone});
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'credential-already-in-use' || 'phone-number-already-exists' =>
          'Este teléfono ya está vinculado a otra cuenta.',
        'provider-already-linked' =>
          'Ya tienes un teléfono vinculado. Desvincúlalo primero.',
        'invalid-verification-code' =>
          'Código incorrecto.',
        _ => e.message ?? 'No se pudo vincular el teléfono (${e.code})',
      });
    }
  }

  /// Vincula una cuenta de Google al usuario actualmente autenticado.
  Future<void> linkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('No hay usuario activo');
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'credential-already-in-use' =>
          'Esta cuenta de Google ya está vinculada a otro usuario.',
        'provider-already-linked' =>
          'Ya tienes una cuenta de Google vinculada.',
        'email-already-in-use' =>
          'El email de esta cuenta de Google ya está en uso por otro usuario.',
        _ => e.message ?? 'No se pudo vincular Google (${e.code})',
      });
    }
  }

  /// Desvincula un proveedor del usuario actual. [providerId] = 'phone',
  /// 'google.com', etc. Mantiene al menos uno para no dejar la cuenta huérfana.
  Future<void> unlinkProvider(String providerId) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('No hay usuario activo');
    if (user.providerData.length <= 1) {
      throw const AuthException(
        'No puedes desvincular el último método de inicio de sesión.',
      );
    }
    try {
      await user.unlink(providerId);
      if (providerId == 'phone') {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .update({'phone': ''});
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'No se pudo desvincular (${e.code})');
    }
  }

  // ─── Alumno: login vía SII + Firebase (con prefill si es nuevo) ────────────

  /// Login para alumnos. Valida primero contra el backend SII; si las
  /// credenciales son correctas, las usa también para Firebase Auth.
  ///
  /// Flujo:
  ///  1. SII.login(email, password) → token + datos del alumno
  ///  2. Persiste el JWT del SII (para consultas posteriores)
  ///  3. Firebase signInWithEmailAndPassword
  ///     - Si user-not-found → createUserWithEmailAndPassword + prefill de
  ///       perfil con `persona`, `email`, `foto`, `numero_control`, `semestre`
  ///     - Si wrong-password → AuthException (la password en SII cambió y
  ///       Firebase tiene la anterior; requiere intervención manual)
  Future<UserCredential> signInStudent({
    required String email,
    required String password,
  }) async {
    // 1) Validar contra SII
    final SiiLoginResponse loginRes;
    try {
      loginRes = await _siiApi.login(email: email, password: password);
    } on SiiApiException catch (e) {
      throw AuthException(
        e.isUnauthorized
            ? 'Credenciales incorrectas en SII.'
            : 'Error al contactar al SII: ${e.message}',
      );
    }
    await _siiTokens.saveToken(loginRes.token);

    // 2) Obtener datos del alumno (los necesitamos por si es primera vez)
    final SiiEstudiante estudiante;
    try {
      estudiante = await _siiApi.getEstudiante(loginRes.token);
    } on SiiApiException catch (e) {
      throw AuthException('No se pudo cargar tu perfil del SII: ${e.message}');
    }

    // 3) Firebase auth con mismas credenciales.
    //
    // Email Enumeration Protection (activada por defecto en Firebase Auth
    // moderno) hace que signIn devuelva `invalid-credential` TANTO para
    // "usuario inexistente" como para "password incorrecta" — son
    // indistinguibles desde el cliente para no filtrar qué emails están
    // registrados. Por eso, ante cualquier credencial inválida intentamos
    // CREAR el usuario; si Firebase responde `email-already-in-use`,
    // entonces sí es un password mismatch real.
    try {
      return await _auth.signInWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      final isCredFailure = e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential';
      if (!isCredFailure) {
        throw AuthException(e.message ?? 'Error de Firebase Auth (${e.code})');
      }

      // Intento de creación: si el email no estaba registrado, esto crea el
      // usuario y el perfil. Si ya existía con otra password, lanza
      // `email-already-in-use` → traducimos a "password desincronizada".
      try {
        final cred = await _auth.createUserWithEmailAndPassword(
            email: email, password: password);
        final uid = cred.user?.uid;
        if (uid != null) {
          await _createStudentProfileFromSii(uid: uid, estudiante: estudiante);
        }
        return cred;
      } on FirebaseAuthException catch (e2) {
        if (e2.code == 'email-already-in-use') {
          // Usuario YA existe en Firebase pero con password distinta a la
          // que SII acaba de validar. Sucede si el alumno cambió su password
          // en el SII después de registrarse en la app.
          throw const AuthException(
            'Tu contraseña en SII no coincide con la registrada en la app. '
            'Contacta al administrador para resincronizarla.',
          );
        }
        throw AuthException(
            e2.message ?? 'Error al crear cuenta (${e2.code})');
      }
    }
  }

  // ─── DEV: registro de alumnos de prueba sin SII ────────────────────────────
  //
  // SOLO debe invocarse desde código gated por `kDebugMode`. Crea un alumno
  // directamente con email+password en Firebase, sin pasar por la validación
  // del SII — pensado para tener varias cuentas dummy con las que probar
  // mensajes, llamadas, grupos, etc. en builds locales.
  //
  // No hay protección a nivel servidor: si esto se llamara en producción,
  // se crearía un alumno legítimo desde la perspectiva de Firestore. Por eso
  // el caller DEBE estar bajo `if (kDebugMode)` y este método no debe
  // exponerse en pantallas de release.
  Future<UserCredential> registerStudentDev({
    required String email,
    required String password,
    required String displayName,
    required String career,
    required int semester,
  }) async {
    // Intento 1: crear el usuario. Si ya existe (común al re-loguear una
    // cuenta dev existente), caemos al intento 2.
    UserCredential cred;
    var wasCreated = true;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Intento 2: sign-in directo con esas credenciales (sin SII).
        wasCreated = false;
        try {
          cred = await _auth.signInWithEmailAndPassword(
              email: email, password: password);
        } on FirebaseAuthException catch (e2) {
          if (e2.code == 'invalid-credential' ||
              e2.code == 'wrong-password' ||
              e2.code == 'user-not-found') {
            throw const AuthException(
                'Esa cuenta ya existe pero la contraseña no coincide.');
          }
          throw AuthException(
              e2.message ?? 'Error al iniciar sesión (${e2.code})');
        }
      } else if (e.code == 'weak-password') {
        throw const AuthException('La contraseña es muy corta (mínimo 6).');
      } else {
        throw AuthException(e.message ?? 'Error al crear cuenta (${e.code})');
      }
    }

    final uid = cred.user!.uid;

    // Solo escribimos el perfil si la cuenta es nueva. Para una cuenta dev
    // ya existente, los campos (carrera/semestre) ya están en Firestore y no
    // queremos pisarlos con los del formulario.
    if (wasCreated) {
      final user = UserModel(
        uid: uid,
        phone: '',
        email: email,
        displayName: displayName,
        avatarUrl: '',
        role: UserRole.student,
        numeroControl: null, // sin numero de control real
        career: career,
        semester: semester,
        department: null,
        isOnline: true,
        lastSeen: DateTime.now(),
        contactIds: [],
        createdAt: DateTime.now(),
      );
      await saveUserProfile(user);
    }
    return cred;
  }

  Future<void> _createStudentProfileFromSii({
    required String uid,
    required SiiEstudiante estudiante,
  }) async {
    final avatarUrl = await _processSiiAvatar(uid, estudiante.foto);
    final user = UserModel(
      uid: uid,
      phone: '', // se vincula después
      email: estudiante.email,
      displayName: estudiante.persona,
      avatarUrl: avatarUrl,
      role: UserRole.student,
      numeroControl: estudiante.numeroControl,
      // SII no devuelve la carrera; el alumno puede editarla luego en perfil.
      career: '',
      semester: estudiante.semestre,
      department: null,
      isOnline: true,
      lastSeen: DateTime.now(),
      contactIds: [],
      createdAt: DateTime.now(),
    );
    await saveUserProfile(user);
  }

  /// El SII devuelve `foto` como base64 (con o sin prefijo `data:image/...;base64,`)
  /// — no como URL. Aquí lo decodificamos a bytes y lo subimos a Supabase
  /// Storage para obtener una URL pública persistente que pueda renderizar
  /// `CachedNetworkImage` en chats, lista de contactos, etc.
  ///
  /// Si la foto está vacía o la decodificación/subida falla, devolvemos
  /// cadena vacía y loggeamos — el avatar caerá al placeholder con iniciales
  /// y el alumno puede subir el suyo manualmente desde Editar perfil.
  Future<String> _processSiiAvatar(String uid, String foto) async {
    if (foto.isEmpty) {
      debugPrint('[SII avatar] campo foto vacío, skip');
      return '';
    }

    // Caso URL absoluta: úsala directo (por si el SII algún día cambia).
    if (foto.startsWith('http://') || foto.startsWith('https://')) {
      return foto;
    }

    // 1) Decodificar base64
    Uint8List bytes;
    try {
      var b64 = foto.trim();
      // Strip del prefijo data URL si está presente: `data:image/jpeg;base64,XXX`
      final commaIdx = b64.indexOf(',');
      if (b64.startsWith('data:') && commaIdx > 0) {
        b64 = b64.substring(commaIdx + 1);
      }
      // El SII devuelve el base64 con saltos de línea cada 76 caracteres
      // (formato MIME estándar), pero `base64.decode` de Dart NO acepta
      // whitespace y falla en el primer `\n`. Removemos cualquier whitespace
      // antes de normalize+decode.
      b64 = b64.replaceAll(RegExp(r'\s'), '');
      // `normalize` agrega padding `=` si falta (algunos backends lo omiten).
      b64 = base64.normalize(b64);
      bytes = base64.decode(b64);
      debugPrint('[SII avatar] decodificado: ${bytes.length} bytes');
      if (bytes.isEmpty) return '';
    } catch (e) {
      debugPrint('[SII avatar] error decodificando base64: $e');
      return '';
    }

    // 2) Subir bytes a Supabase (saltamos XFile.fromData → readAsBytes que en
    // web puede fallar silenciosamente con blob URLs).
    try {
      final url = await StorageService().uploadUserAvatarBytes(uid, bytes);
      debugPrint('[SII avatar] subido OK: $url');
      return url;
    } catch (e, st) {
      debugPrint('[SII avatar] error subiendo a Supabase: $e\n$st');
      return '';
    }
  }

  // ─── Profesor: login Firebase email/password directo (sin SII) ─────────────

  /// Login para profesores. NO crea cuentas — solo permite acceso a profesores
  /// que ya existen en Firebase Auth y tienen perfil en Firestore con role
  /// teacher. Si el rol no es teacher (p.ej. un alumno intentando entrar por
  /// esta vía), deshace el sign-in y lanza [AuthException].
  Future<UserCredential> signInTeacher({
    required String email,
    required String password,
  }) async {
    final UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'user-not-found' => 'No existe una cuenta de profesor con ese correo.',
        'wrong-password' || 'invalid-credential' => 'Contraseña incorrecta.',
        'invalid-email' => 'Correo inválido.',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde.',
        _ => e.message ?? 'Error de autenticación (${e.code})',
      });
    }

    final uid = cred.user?.uid;
    if (uid == null) throw const AuthException('No se obtuvo UID');

    final profile = await getUserProfile(uid);
    if (profile == null) {
      await _auth.signOut();
      throw const AuthException(
        'Esta cuenta no tiene perfil registrado. Contacta al administrador.',
      );
    }
    if (profile.role != UserRole.teacher) {
      await _auth.signOut();
      throw const AuthException(
        'Esta cuenta no es de profesor. Usa el inicio de sesión de alumno.',
      );
    }
    return cred;
  }

  // ─── Google (post-registro; ya no crea cuentas nuevas) ─────────────────────

  /// Sign-in con Google. Solo permite el acceso si el usuario ya tiene perfil
  /// registrado en Firestore — Google ya no es vía de registro inicial.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential =
        GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    final cred = await _auth.signInWithCredential(credential);
    final uid = cred.user?.uid;
    if (uid == null) throw const AuthException('No se obtuvo UID');

    final exists = await userProfileExists(uid);
    if (!exists) {
      // Google creó la cuenta Firebase pero no hay perfil → lo deshacemos.
      try {
        await cred.user?.delete();
      } catch (_) {
        await _auth.signOut();
      }
      throw const AuthException(
        'Esta cuenta de Google no está vinculada a ningún perfil. '
        'Regístrate primero con tu correo institucional.',
      );
    }
    return cred;
  }

  // ─── SII: revalidación on-demand del JWT ──────────────────────────────────

  /// Vuelve a pedir un JWT al SII sin tocar Firebase Auth. Se usa cuando el
  /// alumno entró por teléfono o Google (donde no pasamos por la validación
  /// SII inicial), o cuando el token vigente fue revocado/expiró y queremos
  /// refrescarlo sin cerrar la sesión de Firebase.
  ///
  /// Lanza [AuthException] con mensaje listo para mostrar al usuario.
  Future<void> refreshSiiToken({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _siiApi.login(email: email, password: password);
      await _siiTokens.saveToken(res.token);
    } on SiiApiException catch (e) {
      throw AuthException(
        e.isUnauthorized
            ? 'Contraseña incorrecta en SII.'
            : 'Error al contactar al SII: ${e.message}',
      );
    }
  }

  // ─── Sign-out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _siiTokens.clearToken();
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  // ─── Firestore: perfiles ───────────────────────────────────────────────────

  Future<bool> userProfileExists(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromDoc(doc);
  }

  Future<void> saveUserProfile(UserModel user) async {
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(user.toMap(), SetOptions(merge: true));
  }

  Future<void> updateOnlineStatus(String uid, bool isOnline) async {
    await _firestore.collection('users').doc(uid).update({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}
