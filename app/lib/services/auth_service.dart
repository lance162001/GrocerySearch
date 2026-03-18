import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, Future<void>? googleInitialize})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleInitialize =
            kIsWeb ? Future<void>.value() : (googleInitialize ?? GoogleSignIn.instance.initialize()) {
    _auth!.authStateChanges().listen((_) => notifyListeners());
  }

  @visibleForTesting
  AuthService.test()
      : _auth = null,
        _googleInitialize = Future<void>.value();

  final FirebaseAuth? _auth;
  final Future<void> _googleInitialize;

  User? get currentUser => _auth?.currentUser;
  bool get isSignedIn => currentUser != null;
  String? get displayName => currentUser?.displayName;
  String? get email => currentUser?.email;
  String? get photoUrl => currentUser?.photoURL;

  Stream<User?> get authStateChanges => _auth!.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      return _auth!.signInWithPopup(provider);
    }

    await _googleInitialize;

    GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted ||
          e.code == GoogleSignInExceptionCode.uiUnavailable) {
        return null;
      }
      rethrow;
    }

    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return _auth!.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleInitialize;
      await GoogleSignIn.instance.signOut();
    }
    await _auth!.signOut();
  }
}
