import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';

/// One box per digit of the verification code.
///
/// Boxes are the right control here because the code has a fixed, known length:
/// the user can see how much is still missing, and the keyboard can be forced to
/// numeric input. It also makes paste a one-tap operation.
class OtpInput extends StatefulWidget {
  const OtpInput({
    required this.length,
    required this.onChanged,
    super.key,
    this.onCompleted,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onChanged;

  /// Called once the final box is filled, so the caller can verify immediately
  /// instead of making the user hunt for a submit button.
  final VoidCallback? onCompleted;
  final bool enabled;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focuses;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focuses = List<FocusNode>.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    for (final FocusNode f in _focuses) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((TextEditingController c) => c.text).join();

  void _emit() => widget.onChanged(_value);

  void _onChanged(int index, String text) {
    final String digit = text.isEmpty ? '' : text.characters.last;
    _controllers[index].text = digit;
    _emit();

    if (digit.isNotEmpty && index < widget.length - 1) {
      _focuses[index + 1].requestFocus();
    } else if (digit.isEmpty && index > 0) {
      _focuses[index - 1].requestFocus();
    } else if (digit.isNotEmpty && index == widget.length - 1) {
      // The last box is full: the caller can verify right away.
      _focuses[index].unfocus();
      widget.onCompleted?.call();
    }
  }

  void _done(int index) {
    if (_value.length != widget.length) return;
    _focuses[index].unfocus();
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder so each box is sized relative to available width,
    // preventing overflow on narrow screens (e.g. 360 dp devices).
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Total gap width between `length` boxes = (length - 1) * AppSpacing.sm
        final double totalGap = (widget.length - 1) * AppSpacing.sm;
        final double boxWidth =
            ((constraints.maxWidth - totalGap) / widget.length).clamp(36.0, 56.0);
        final double boxHeight = (boxWidth * 58 / 48).clamp(44.0, 68.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < widget.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: boxWidth,
                height: boxHeight,
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focuses[i],
                  enabled: widget.enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: i == widget.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  maxLength: 1,
                  obscureText: false,
                  showCursor: true,
                  // A digit field has nothing for the IME to suggest: a suggestion
                  // strip floating over the row reads as a stray message that
                  // appears exactly when the last box is typed.
                  enableSuggestions: false,
                  autocorrect: false,
                  style: Theme.of(context).textTheme.titleLarge,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  decoration:
                      const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero),
                  onChanged: (String value) => _onChanged(i, value),
                  onSubmitted: (_) => _done(i),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Verifies the account before the app is unlocked.
///
/// The code is delivered to the phone number or email address the user
/// registered, by the configured gateway. It is never displayed here: if the
/// device could read the code by itself, verification would prove nothing about
/// who owns that destination.
class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  String _code = '';
  bool _busy = false;

  /// Tracks the resend cooldown so the button cannot be spammed.
  bool _onCooldown = false;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resend());
  }

  Future<void> _resend() async {
    if (_onCooldown) return;
    final AuthProvider auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _onCooldown = true;
    });
    if (!mounted) return;
    await auth.sendOtp();
    if (!mounted) return;
    setState(() => _busy = false);

    // Enforce the cooldown window defined in AppConstants so the user cannot
    // flood the gateway. The initial send on screen load also starts the timer
    // so the button is disabled for the first 30 seconds.
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(AppConstants.otpResendCooldown, () {
      if (mounted) setState(() => _onCooldown = false);
    });
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (Validators.otp(_code) != null) return;
    setState(() => _busy = true);
    if (!mounted) return;
    final bool ok = await context.read<AuthProvider>().verifyOtp(_code);
    if (!mounted) return;
    setState(() => _busy = false);
    // On success the stage becomes `authenticated` and AuthGate swaps the
    // dashboard in, so there is nothing to navigate to here.
    if (!ok) {
      final AuthProvider auth = context.read<AuthProvider>();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.error ?? 'That code is not correct.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations s = AppLocalizations.of(context);
    final AuthProvider auth = context.watch<AuthProvider>();
    final bool canVerify = _code.length == AppConstants.otpLength && !_busy;

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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(
                        Icons.mark_email_read_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(s.verifyAccount, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    s.verifySubtitle.replaceFirst('your email', _masked(auth.user?.email ?? '')),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  OtpInput(
                    length: AppConstants.otpLength,
                    enabled: !_busy,
                    onChanged: (String value) => setState(() => _code = value),
                    onCompleted: _busy ? null : _verify,
                  ),
                  if (auth.error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      auth.error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: canVerify ? _verify : null,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(s.verifyAndContinue),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: (_busy || _onCooldown) ? null : _resend,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_onCooldown ? 'Please wait…' : s.sendNewCode),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    s.nothingArrived,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
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

/// Hides most of a destination so the screen confirms *where* the code went
/// without putting the full number or address back on the display.
String _masked(String destination) {
  if (destination.isEmpty) return 'your contact details';
  if (destination.length <= 4) return '••••';
  return '${destination.substring(0, 2)}${'•' * (destination.length - 4)}'
      '${destination.substring(destination.length - 2)}';
}

