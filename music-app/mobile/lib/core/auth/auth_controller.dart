import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AuthController extends ChangeNotifier {
  final SupabaseClient client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  bool _loading = true;

  AuthController() {
    _session = client.auth.currentSession;
    _loading = false;
    _subscription = client.auth.onAuthStateChange.listen((state) {
      _session = state.session;
      notifyListeners();
    });
  }

  Session? get session => _session;
  User? get user => _session?.user;
  bool get loading => _loading;
  bool get isAuthenticated => user != null;
  String get displayName =>
      (user?.userMetadata?['display_name'] ??
              user?.userMetadata?['full_name'] ??
              user?.userMetadata?['name'] ??
              user?.email?.split('@').first ??
              'InnerWave Listener')
          .toString();

  Future<String?> signIn(String email, String password) async {
    try {
      await client.auth.signInWithPassword(email: email.trim(), password: password);
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not sign in. Check your connection and try again.';
    }
  }

  Future<({String? error, bool verificationRequired})> signUp(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: SupabaseConfig.mobileCallback,
        data: {'display_name': name.trim()},
      );
      return (error: null, verificationRequired: response.session == null);
    } on AuthException catch (error) {
      return (error: error.message, verificationRequired: false);
    } catch (_) {
      return (error: 'Could not create your account. Try again.', verificationRequired: false);
    }
  }

  Future<String?> signInWithGoogle() async {
    try {
      await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.mobileCallback,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not open Google sign-in.';
    }
  }

  Future<void> signOut() => client.auth.signOut();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
