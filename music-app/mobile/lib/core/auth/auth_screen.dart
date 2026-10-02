import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _verificationSent = false;
  bool _forgotPassword = false;
  bool _resetSent = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    if (_signUp) {
      final result = await auth.signUp(_name.text, _email.text, _password.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = result.error;
        _verificationSent = result.verificationRequired;
      });
    } else {
      final error = await auth.signIn(_email.text, _password.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<AuthController>().signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<AuthController>().resendVerification(
      _email.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent again.')),
      );
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<AuthController>().sendPasswordReset(
      _email.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _resetSent = error == null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                color: const Color(0xFF151817),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _forgotPassword
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              _resetSent
                                  ? Icons.mark_email_read_outlined
                                  : Icons.lock_reset,
                              size: 54,
                              color: const Color(0xFFD5FF63),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _resetSent
                                  ? 'Check your email'
                                  : 'Reset your password',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _resetSent
                                  ? 'We sent a secure password reset link to ${_email.text.trim()}.'
                                  : 'Enter your account email and we’ll send you a secure reset link.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white60),
                            ),
                            if (!_resetSent) ...[
                              const SizedBox(height: 22),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _sendPasswordReset(),
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                ),
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _busy ? null : _sendPasswordReset,
                                child: Text(
                                  _busy ? 'Please wait…' : 'Send reset link',
                                ),
                              ),
                            ],
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _forgotPassword = false;
                                      _resetSent = false;
                                      _error = null;
                                    }),
                              icon: const Icon(Icons.arrow_back, size: 16),
                              label: const Text('Back to sign in'),
                            ),
                          ],
                        )
                      : _verificationSent
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mark_email_read_outlined,
                              size: 54,
                              color: Color(0xFFD5FF63),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Verify your email',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'We sent a verification link to ${_email.text}. Verify it, then sign in.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white60),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: _busy ? null : _resend,
                              child: Text(
                                _busy
                                    ? 'Please wait…'
                                    : 'Resend verification email',
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _verificationSent = false;
                                _signUp = false;
                              }),
                              child: const Text('Back to sign in'),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  backgroundColor: Color(0xFFD5FF63),
                                  child: Icon(
                                    Icons.graphic_eq,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'InnerWave',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              _signUp ? 'Create your account' : 'Welcome back',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 22),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _google,
                              icon: const Text(
                                'G',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              label: const Text('Continue with Google'),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                            ),
                            if (_signUp) ...[
                              TextField(
                                controller: _name,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: true,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Password',
                              ),
                            ),
                            if (!_signUp)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _forgotPassword = true;
                                          _error = null;
                                        }),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy
                                    ? 'Please wait…'
                                    : (_signUp ? 'Create account' : 'Sign in'),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _signUp = !_signUp;
                                      _error = null;
                                    }),
                              child: Text(
                                _signUp
                                    ? 'Already have an account? Sign in'
                                    : 'New to InnerWave? Create account',
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (_, auth, _) {
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.passwordRecovery) return const ResetPasswordScreen();
        return auth.isAuthenticated ? child : const AuthScreen();
      },
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<AuthController>().updatePassword(
      _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: const Color(0xFF151817),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.lock_reset,
                      size: 54,
                      color: Color(0xFFD5FF63),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Create a new password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a strong password for your InnerWave account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPassword,
                      obscureText: true,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Please wait…' : 'Update password'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : context
                                .read<AuthController>()
                                .cancelPasswordRecovery,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
