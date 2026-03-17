import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance {
    _auth!.authStateChanges().listen((_) => notifyListeners());
  }

  @visibleForTesting
  AuthService.test() : _auth = null;

  final FirebaseAuth? _auth;

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

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth!.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      await GoogleSignIn().signOut();
    }
    await _auth!.signOut();
  }
}
