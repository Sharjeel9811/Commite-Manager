import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';

/// First-run account creation.
///
/// The provider decides *whether* the form is valid; this screen only collects
/// the text and shows the messages. Every rule the user can break — name, phone,
/// email, PIN, matching PIN — is declared once in [Validators] and enforced again
/// inside `AuthService`, so a bypassed UI cannot create a bad row.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirmPin = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final AuthProvider auth = context.read<AuthProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final bool ok = await auth.register(
        fullName: _name.text.trim(),
        phoneNumber: _phone.text.trim(),
        email: _email.text.trim(),
        pin: _pin.text,
        confirmPin: _confirmPin.text,
      );
      if (!mounted) return;
      if (!ok) {
        _showError(messenger, auth.error ?? 'Could not create your account.');
        return;
      }
      // Registration completes locally; AuthGate now reveals the app shell.
    } on ValidationException catch (error) {
      if (!mounted) return;
      _showError(messenger, error.message);
    } catch (error) {
      if (!mounted) return;
      _showError(messenger, describeError(error));
    }
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations s = AppLocalizations.of(context);
    final bool busy = context.select<AuthProvider, bool>((AuthProvider p) => p.isBusy);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _BrandHeader(
                      title: s.createAccount,
                      subtitle: s.createAccountSubtitle,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: s.fullName,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      validator: (String? value) => Validators.requiredText(
                        value,
                        fieldName: 'Name',
                        maxLength: AppConstants.maxMemberNameLength,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: s.phoneOptional,
                        helperText: s.phoneHelper,
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      validator: Validators.optionalPhoneNumber,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: s.emailAddress,
                        helperText: s.emailHelper,
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                      ),
                      validator: (String? value) => Validators.email(value, required: true),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: s.pin46,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        counterText: '',
                      ),
                      validator: (String? value) => Validators.pin(value, isConfirmation: false),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _confirmPin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: s.confirmPin,
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        counterText: '',
                      ),
                      validator: (String? value) {
                        final String? basic = Validators.pin(value, isConfirmation: true);
                        if (basic != null) return basic;
                        if (value != _pin.text) return 'PINs do not match';
                        return null;
                      },
                      onFieldSubmitted: (_) => busy ? null : _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(s.createAccount),
                    ),
                    const SizedBox(height: AppSpacing.lg),
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
                            s.pinStorageNote,
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
      ),
    );
  }
}

/// Shared lockup used by the register screen.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
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
              Icons.groups_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
