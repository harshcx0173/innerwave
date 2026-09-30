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
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthController>();
    if (_signUp) {
      final result = await auth.signUp(_name.text, _email.text, _password.text);
      if (!mounted) return;
      setState(() { _busy = false; _error = result.error; _verificationSent = result.verificationRequired; });
    } else {
      final error = await auth.signIn(_email.text, _password.text);
      if (!mounted) return;
      setState(() { _busy = false; _error = error; });
    }
  }

  Future<void> _google() async {
    setState(() { _busy = true; _error = null; });
    final error = await context.read<AuthController>().signInWithGoogle();
    if (!mounted) return;
    setState(() { _busy = false; _error = error; });
  }

  Future<void> _resend() async {
    setState(() { _busy = true; _error = null; });
    final error = await context.read<AuthController>().resendVerification(_email.text);
    if (!mounted) return;
    setState(() { _busy = false; _error = error; });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent again.')),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose();
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
                  child: _verificationSent
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mark_email_read_outlined, size: 54, color: Color(0xFFD5FF63)),
                          const SizedBox(height: 18),
                          const Text('Verify your email', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          Text('We sent a verification link to ${_email.text}. Verify it, then sign in.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
                          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
                          const SizedBox(height: 22),
                          FilledButton(onPressed: _busy ? null : _resend, child: Text(_busy ? 'Please wait…' : 'Resend verification email')),
                          TextButton(onPressed: () => setState(() { _verificationSent = false; _signUp = false; }), child: const Text('Back to sign in')),
                        ])
                      : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircleAvatar(backgroundColor: Color(0xFFD5FF63), child: Icon(Icons.graphic_eq, color: Colors.black)), SizedBox(width: 10), Text('InnerWave', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))]),
                          const SizedBox(height: 28),
                          Text(_signUp ? 'Create your account' : 'Welcome back', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 22),
                          OutlinedButton.icon(onPressed: _busy ? null : _google, icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900)), label: const Text('Continue with Google')),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: TextStyle(color: Colors.white38, fontSize: 11))), Expanded(child: Divider())])),
                          if (_signUp) ...[TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Name')), const SizedBox(height: 12)],
                          TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email')),
                          const SizedBox(height: 12),
                          TextField(controller: _password, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Password')),
                          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                          const SizedBox(height: 18),
                          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Please wait…' : (_signUp ? 'Create account' : 'Sign in'))),
                          TextButton(onPressed: _busy ? null : () => setState(() { _signUp = !_signUp; _error = null; }), child: Text(_signUp ? 'Already have an account? Sign in' : 'New to InnerWave? Create account')),
                        ]),
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
    return Consumer<AuthController>(builder: (_, auth, __) {
      if (auth.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return auth.isAuthenticated ? child : const AuthScreen();
    });
  }
}
