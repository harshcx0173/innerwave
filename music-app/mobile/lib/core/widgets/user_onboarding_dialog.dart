import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

const List<String> kSuggestionPool = [
  'Wave Rider',
  'Sonic Nomad',
  'Aura Groove',
  'Neon Rhythm',
  'Echo Chaser',
  'Velvet Beats',
  'Melody Seeker',
  'Cosmic Flow',
  'Midnight Chords',
  'Solar Harmony',
  'Bass Voyager',
  'Indie Pulse',
  'Rhythm Nomad',
  'Audio Explorer',
  'Luna Grooves',
  'Electric Soul',
];

class UserOnboardingDialog extends StatefulWidget {
  final Function(String name) onComplete;

  const UserOnboardingDialog({super.key, required this.onComplete});

  static Future<void> checkAndShow(BuildContext context, Function(String) onSave) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('innerwave_user_name');
    if (name == null || name.trim().isEmpty) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (context) => UserOnboardingDialog(
          onComplete: (enteredName) async {
            await prefs.setString('innerwave_user_name', enteredName);
            onSave(enteredName);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      );
    } else {
      onSave(name);
    }
  }

  @override
  State<UserOnboardingDialog> createState() => _UserOnboardingDialogState();
}

class _UserOnboardingDialogState extends State<UserOnboardingDialog> {
  final TextEditingController _controller = TextEditingController();
  List<String> _suggestions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _shuffleSuggestions();
  }

  void _shuffleSuggestions() {
    final pool = List<String>.from(kSuggestionPool)..shuffle();
    setState(() {
      _suggestions = pool.take(6).toList();
    });
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = 'Please enter your name or pick a suggestion.');
      return;
    }
    if (trimmed.length < 2) {
      setState(() => _error = 'Name must be at least 2 characters.');
      return;
    }
    widget.onComplete(trimmed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Non-dismissible
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1012),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.border),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 40, spreadRadius: 10),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.headphones, color: Colors.black, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, color: AppTheme.accent, size: 13),
                            SizedBox(width: 4),
                            Text(
                              'WELCOME TO INNERWAVE',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(
                          'What should we call you?',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Personalize your private music stream, personalized shelves, and player experience.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Alex, Sonic Nomad, MelodySeeker',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0x12FFFFFF),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.accent),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'OR PICK A SUGGESTION:',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  GestureDetector(
                    onTap: _shuffleSuggestions,
                    child: const Row(
                      children: [
                        Icon(Icons.refresh, color: AppTheme.accent, size: 14),
                        SizedBox(width: 4),
                        Text('Shuffle', style: TextStyle(color: AppTheme.accent, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _suggestions.map((suggestion) {
                  final isSelected = _controller.text == suggestion;
                  return ChoiceChip(
                    label: Text(suggestion),
                    selected: isSelected,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    selectedColor: AppTheme.accent,
                    backgroundColor: const Color(0x10FFFFFF),
                    side: BorderSide(
                      color: isSelected ? AppTheme.accent : AppTheme.border,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) {
                      setState(() {
                        _controller.text = suggestion;
                        _error = null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Start Listening', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
