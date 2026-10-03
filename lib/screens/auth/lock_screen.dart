import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';

/// The PIN screen, used both on first unlock and after a lockout.
///
/// The same widget serves both cases: a lockout offers "verify by code" while an
/// ordinary unlock does not, and the countdown is derived from the provider
/// rather than from a local timer so it cannot drift out of sync with the
/// authoritative `locked_until` column.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _pin = TextEditingController();
  String _error = '';
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Use the device's own face / fingerprint the moment the lock appears,
    // instead of making the user find a button first. The manual button below
    // stays as a fallback for when the native prompt is dismissed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AuthProvider auth = context.read<AuthProvider>();
      if (auth.biometricAvailable && auth.biometricEnabled && !auth.isLockedOut) {
        _biometric(auth);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock(AuthProvider auth) async {
    if (Validators.pin(_pin.text, isConfirmation: false) != null) {
      setState(() => _error = 'Enter your $minMaxPin PIN');
      return;
    }
    setState(() => _error = '');

    final bool ok = await auth.unlock(_pin.text);
    if (!mounted) return;
    if (ok) {
      _pin.clear();
      return;
    }
    setState(() => _error = auth.error ?? 'Wrong PIN');
  }

  Future<void> _biometric(AuthProvider auth) async {
    final bool ok = await auth.unlockWithBiometrics();
    if (!mounted) return;
    if (!ok) setState(() => _error = auth.error ?? 'Biometric unlock failed');
  }

  Future<void> _recover(AuthProvider auth) async {
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext _) => const _OtpRecoveryDialog(),
    );
    if (code == null || !mounted) return;
    final bool ok = await auth.recoverWithOtp(code);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = auth.error ?? 'That code is not correct.');
    }
  }
  String get minMaxPin => '${AppConstants.minPinLength}-${AppConstants.maxPinLength}';

  Duration? get _remaining {
    final DateTime? until = context.read<AuthProvider>().lockedUntil;
    if (until == null) return null;
    final Duration left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations s = AppLocalizations.of(context);
    final AuthProvider auth = context.watch<AuthProvider>();
    final Duration? remaining = _remaining;
    final bool lockedOut = remaining != null;
    final String? serverError = _error.isNotEmpty ? _error : (lockedOut ? null : auth.error);

    final int expectedLength = (auth.user?.pinLength ?? AppConstants.minPinLength).clamp(
      AppConstants.minPinLength,
      AppConstants.maxPinLength,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: lockedOut
                            ? AppColors.danger.withValues(alpha: 0.12)
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Icon(
                        lockedOut ? Icons.lock_clock_rounded : Icons.lock_rounded,
                        size: 34,
                        color: lockedOut ? AppColors.danger : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    lockedOut ? s.tooManyAttempts : s.welcomeBack,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lockedOut
                        ? '${s.lockedFor} ${_formatRemaining(remaining)}'
                        : '${s.enterPin} ${auth.fullName}',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!lockedOut)
                    Text(
                      s.pinHint,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (!lockedOut) ...<Widget>[
                    _PinPad(
                      onDigit: (String digit) {
                        if (_pin.text.length < AppConstants.maxPinLength) {
                          _pin.text += digit;
                        }
                      },
                      onBackspace: () {
                        if (_pin.text.isNotEmpty) {
                          _pin.text = _pin.text.substring(0, _pin.text.length - 1);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List<Widget>.generate(
                        expectedLength,
                        (int i) => Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.text.length
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: auth.isBusy || _pin.text.isEmpty ? null : () => _unlock(auth),
                      child: auth.isBusy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(s.unlock),
                    ),
                    if (auth.biometricAvailable && auth.biometricEnabled) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: auth.isBusy ? null : () => _biometric(auth),
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: Text(s.useBiometrics),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: auth.isBusy ? null : () => _recover(auth),
                      child: Text(s.forgotPin),
                    ),
                  ] else ...<Widget>[
                    FilledButton.icon(
                      onPressed: auth.isBusy ? null : () => _recover(auth),
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: Text(s.verifyWithCode),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      s.lockoutNote,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (serverError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      serverError,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatRemaining(Duration d) {
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// A numeric keypad. Preferred over a text field because it cannot produce a
/// non-digit and works one-handed on a large phone.
class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.7,
      children: <Widget>[
        for (int i = 1; i <= 9; i++) _Key(label: '$i', onTap: () => onDigit('$i')),
        const SizedBox.shrink(),
        _Key(label: '0', onTap: () => onDigit('0')),
        _Key(icon: Icons.backspace_outlined, onTap: onBackspace),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22, color: scheme.onSurface)
              : Text(
                  label!,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}

/// Sends a recovery code, then collects the one the user received.
///
/// The send happens **here**, before the code is asked for. Asking first and
/// sending afterwards (or not at all) is what made this screen impossible to
/// complete: no challenge existed, so every code was rejected with "request a
/// new verification code" and the user was stuck.
class _OtpRecoveryDialog extends StatefulWidget {
  const _OtpRecoveryDialog();

  @override
  State<_OtpRecoveryDialog> createState() => _OtpRecoveryDialogState();
}

class _OtpRecoveryDialogState extends State<_OtpRecoveryDialog> {
  final TextEditingController _controller = TextEditingController();

  /// null while the send is still in flight.
  String? _sendError;
  bool _sent = false;
  bool _sending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  Future<void> _send() async {
    final AuthProvider auth = context.read<AuthProvider>();
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final bool ok = await auth.sendOtp();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = ok;
      _sendError = ok ? null : (auth.error ?? 'The code could not be sent.');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();
    final AppUser? user = auth.user;
    final String target = _maskTarget(user?.email ?? '');

    return AlertDialog(
      title: const Text('Verify your identity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_sending) ...<Widget>[
            const Row(
              children: <Widget>[
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Sending a one-time code...')),
              ],
            ),
          ] else if (_sent) ...<Widget>[
            Text(
              'A 6-digit code was sent to $target. '
              'Enter it below to unlock.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: AppConstants.otpLength,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                counterText: '',
                labelText: '6-digit code from the message',
              ),
            ),
          ] else ...<Widget>[
            Text(
              'We could not send a code to $target.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _sendError ?? 'Please try again.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nothing arrived? Check your spam folder and wait a minute before requesting a new code.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (_sent) ...<Widget>[
          TextButton(
            onPressed: _sending ? null : _send,
            child: const Text('Resend'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Unlock'),
          ),
        ] else if (!_sending) ...<Widget>[
          FilledButton(onPressed: _send, child: const Text('Try again')),
        ],
      ],
    );
  }
}

String _maskTarget(String value) {
  if (value.isEmpty) return 'your contact details on this account';
  if (value.length <= 4) return '••••';
  return '${value.substring(0, 2)}${'•' * (value.length - 4)}'
      '${value.substring(value.length - 2)}';
}
