import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  bool _initialized = false;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _name.text = context.read<AuthController>().displayName;
      _initialized = true;
    }
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((part) => part.isEmpty ? '' : part[0])
      .join()
      .toUpperCase();

  Future<void> _save() async {
    final value = _name.text.trim();
    if (value.length < 2) {
      setState(() => _error = 'Display name must be at least 2 characters.');
      return;
    }
    if (value.length > 40) {
      setState(() => _error = 'Display name cannot exceed 40 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final error = await context.read<AuthController>().updateDisplayName(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _message = error == null ? 'Profile updated on all your devices.' : null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final provider = auth.user?.appMetadata['provider']?.toString() ?? 'email';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF253018), Color(0xFF121512)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 37,
                  backgroundColor: AppTheme.accent,
                  child: Text(
                    _initials(auth.displayName),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR INNERWAVE PROFILE',
                        style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        auth.displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        auth.user?.email ?? '',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_outline, color: AppTheme.accent),
                      SizedBox(width: 10),
                      Text(
                        'Profile details',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      helperText: 'Shared across web and mobile',
                    ),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  if (_message != null)
                    Text(
                      _message!,
                      style: const TextStyle(
                        color: Color(0xFFA9EDB2),
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(_busy ? 'Saving…' : 'Save changes'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppTheme.accent,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _detail(
                    'Sign-in method',
                    provider == 'google' ? 'Google' : 'Email & password',
                  ),
                  const Divider(height: 25),
                  _detail(
                    'Email status',
                    auth.user?.emailConfirmedAt != null
                        ? 'Verified'
                        : 'Pending',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    await auth.signOut();
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Color(0x55FF5252)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out of InnerWave'),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    ],
  );
}
