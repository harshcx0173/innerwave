import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AuthController extends ChangeNotifier {
  final SupabaseClient client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  bool _loading = true;
  bool _passwordRecovery = false;

  AuthController() {
    _session = client.auth.currentSession;
    _loading = false;
    _subscription = client.auth.onAuthStateChange.listen((state) {
      _session = state.session;
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecovery = true;
      } else if (state.event == AuthChangeEvent.signedOut) {
        _passwordRecovery = false;
      }
      notifyListeners();
    });
  }

  Session? get session => _session;
  User? get user => _session?.user;
  bool get loading => _loading;
  bool get isAuthenticated => user != null;
  bool get passwordRecovery => _passwordRecovery;
  String get displayName =>
      (user?.userMetadata?['display_name'] ??
              user?.userMetadata?['full_name'] ??
              user?.userMetadata?['name'] ??
              user?.email?.split('@').first ??
              'InnerWave Listener')
          .toString();

  Future<String?> signIn(String email, String password) async {
    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
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
      return (
        error: 'Could not create your account. Try again.',
        verificationRequired: false,
      );
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

  Future<String?> resendVerification(String email) async {
    try {
      await client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: SupabaseConfig.mobileCallback,
      );
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not resend the verification email. Try again.';
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: SupabaseConfig.mobileCallback,
      );
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not send the password reset email. Try again.';
    }
  }

  Future<String?> updatePassword(String password) async {
    try {
      await client.auth.updateUser(UserAttributes(password: password));
      _passwordRecovery = false;
      notifyListeners();
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not update your password. Try again.';
    }
  }

  Future<String?> updateDisplayName(String name) async {
    try {
      await client.auth.updateUser(
        UserAttributes(data: {'display_name': name.trim()}),
      );
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not update your profile. Try again.';
    }
  }

  void cancelPasswordRecovery() {
    _passwordRecovery = false;
    notifyListeners();
  }

  Future<void> signOut() => client.auth.signOut();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
