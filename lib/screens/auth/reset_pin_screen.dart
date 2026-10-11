import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_spacing.dart';
import '../../providers/auth_provider.dart';

/// Full-screen page shown after OTP recovery succeeds.
///
/// Flow:
///   Lock screen → "Forgot PIN?" → OTP dialog → [this screen] → Dashboard
///
/// The user types a new PIN here. Once saved the app opens directly — they do
/// NOT have to re-enter it right away.
class ResetPinScreen extends StatefulWidget {
  const ResetPinScreen({super.key});

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final TextEditingController _pin        = TextEditingController();
  final TextEditingController _confirmPin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String pin     = _pin.text.trim();
    final String confirm = _confirmPin.text.trim();

    if (pin.length < AppConstants.minPinLength ||
        pin.length > AppConstants.maxPinLength) {
      setState(() => _error =
          'PIN must be ${AppConstants.minPinLength}–'
          '${AppConstants.maxPinLength} digits.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match.');
      return;
    }

    final AuthProvider auth = context.read<AuthProvider>();
    final bool ok = await auth.completePinReset(pin, confirm);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = auth.error ?? 'Could not save PIN. Try again.');
    }
    // On success AuthGate switches to authenticated automatically.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthProvider auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Icon
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        size: 36,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Title
                  Text(
                    'Set a new PIN',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Your identity has been verified.\n'
                    'Choose a ${AppConstants.minPinLength}–'
                    '${AppConstants.maxPinLength} digit PIN to protect your app.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // New PIN
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: AppConstants.maxPinLength,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText:
                          'New PIN (${AppConstants.minPinLength}–'
                          '${AppConstants.maxPinLength} digits)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Confirm PIN
                  TextField(
                    controller: _confirmPin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: AppConstants.maxPinLength,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new PIN',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => auth.isBusy ? null : _save(),
                  ),

                  // Error message
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xxl),

                  // Save button
                  FilledButton(
                    onPressed: auth.isBusy ? null : _save,
                    child: auth.isBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Save PIN and open app'),
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  // Security note
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Your PIN is encrypted before being stored. '
                          'Every time you open the app from now on, '
                          'this new PIN will be used.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
