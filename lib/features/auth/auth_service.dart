import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _providedAuth = auth;

  final FirebaseAuth? _providedAuth;
  bool _googleInitialized = false;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.sendEmailVerification();
    return credential;
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> resendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  Future<bool> refreshEmailVerification() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<UserCredential> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) return _auth.signInWithPopup(provider);

    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }
    late final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelledException();
      }
      rethrow;
    }
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithApple() {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return kIsWeb
        ? _auth.signInWithPopup(provider)
        : _auth.signInWithProvider(provider);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
  }
}

class AuthCancelledException implements Exception {
  const AuthCancelledException();
}
