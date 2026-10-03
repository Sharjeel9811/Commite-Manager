import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_settings.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../providers/committee_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_card.dart';

/// Preferences, security, notifications, data and about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations s = AppLocalizations.of(context);
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final AuthProvider auth = context.watch<AuthProvider>();
    final LocaleProvider locale = context.watch<LocaleProvider>();
    final AppSettings preferences = settings.preferences;

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          _ProfileCard(auth: auth, s: s),
          const SizedBox(height: AppSpacing.xl),

          // ---- Language -----------------------------------------------
          SectionLabel(s.language),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: <Widget>[
                for (final AppLanguage lang in AppLanguage.values)
                  RadioListTile<AppLanguage>(
                    value: lang,
                    groupValue: locale.language,
                    title: Text(
                      lang.label,
                      style: lang == AppLanguage.urdu
                          ? theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: 'Jameel Noori Nastaleeq',
                            )
                          : null,
                    ),
                    secondary: Text(
                      lang == AppLanguage.urdu ? 'اردو' : 'EN',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    onChanged: (AppLanguage? value) {
                      if (value != null) locale.setLanguage(value);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Appearance ----------------------------------------------
          SectionLabel(s.appearance),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: RadioGroup<AppThemePreference>(
              groupValue: preferences.themePreference,
              onChanged: (AppThemePreference? value) {
                if (value != null) settings.setTheme(value);
              },
              child: Column(
                children: <Widget>[
                  for (final AppThemePreference option in AppThemePreference.values)
                    RadioListTile<AppThemePreference>(
                      value: option,
                      title: Text(option.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Currency -----------------------------------------------
          SectionLabel(s.currency),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: RadioGroup<_Currency>(
              groupValue: _currencies.firstWhere(
                (_Currency c) => c.code == preferences.currencyCode,
                orElse: () => _currencies.first,
              ),
              onChanged: (_Currency? value) {
                if (value != null) {
                  settings.setCurrency(
                    code: value.code,
                    symbol: value.symbol,
                    decimals: value.decimals,
                  );
                }
              },
              child: Column(
                children: <Widget>[
                  for (final _Currency option in _currencies)
                    RadioListTile<_Currency>(
                      value: option,
                      title: Text('${option.symbol}  ${option.label}'),
                      subtitle: Text(option.code),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Notifications ------------------------------------------
          SectionLabel(s.notifications),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  value: preferences.notificationsEnabled,
                  onChanged: settings.setNotificationsEnabled,
                  title: Text(s.paymentReminders),
                  subtitle: Text(s.paymentRemindersSubtitle),
                  secondary: const Icon(Icons.notifications_active_outlined),
                ),
                if (preferences.notificationsEnabled) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    title: Text(s.reminderTime),
                    subtitle: Text(
                      '${preferences.dailyReminderHour.toString().padLeft(2, '0')}:00',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickReminderHour(context, settings),
                  ),
                  if (settings.scheduledCount > 0) ...<Widget>[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.event_available_rounded, size: 18),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              '${settings.scheduledCount} reminder(s) scheduled',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Security -----------------------------------------------
          SectionLabel(s.security),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  value: preferences.lockEnabled,
                  onChanged: settings.setLockEnabled,
                  title: Text(s.requirePin),
                  subtitle: Text(s.requirePinSubtitle),
                  secondary: const Icon(Icons.lock_outline_rounded),
                ),
                if (preferences.lockEnabled) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(s.lockAfter),
                    subtitle: Text(
                      'The app locks itself after ${_idleLabel(preferences.lockTimeoutMinutes)} '
                      'without any interaction.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickIdleTimeout(context, settings),
                  ),
                ],
                if (auth.biometricAvailable) ...<Widget>[
                  const Divider(height: 1),
                  SwitchListTile(
                    value: auth.biometricEnabled,
                    onChanged: auth.setBiometricEnabled,
                    title: Text(s.unlockWithBiometrics),
                    subtitle: Text(s.unlockWithBiometricsSubtitle),
                    secondary: const Icon(Icons.fingerprint_rounded),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pin_rounded),
                  title: Text(s.changePin),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _changePin(context, auth, s),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_clock_rounded),
                  title: Text(s.lockNow),
                  onTap: auth.lock,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Verification codes -------------------------------------
          SectionLabel(s.verificationCodes),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: Text(s.howCodesDelivered),
                  subtitle: Text(
                    '${settings.otpDeliveryDescription}. '
                    'The code is never displayed inside the app.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Data ---------------------------------------------------
          SectionLabel(s.data),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(settings.hasSampleData ? 'Remove sample data' : s.sampleData),
                  subtitle: Text(s.sampleDataSubtitle),
                  trailing: settings.isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: settings.isBusy
                      ? null
                      : () async {
                          final String? message = settings.hasSampleData
                              ? await settings.removeSampleData()
                              : await settings.loadSampleData();
                          if (!context.mounted || message == null) return;
                          if (context.mounted) {
                            await context.read<CommitteeProvider>().load();
                          }
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(message)));
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: Text(s.resetPreferences),
                  subtitle: Text(s.resetPreferencesSubtitle),
                  onTap: () async {
                    await settings.resetPreferences();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.preferencesReset)),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                  title: Text(
                    s.deleteAllCommittees,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  subtitle: Text(s.deleteAllCommitteesSubtitle),
                  onTap: () => _eraseAll(context, settings, s),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_remove_rounded, color: AppColors.danger),
                  title: Text(
                    s.deleteAccount,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  subtitle: Text(s.deleteAccountSubtitle),
                  onTap: () => _deleteAccount(context, auth, settings, s),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- About --------------------------------------------------
          SectionLabel(s.about),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                _AboutRow(
                  icon: Icons.info_outline_rounded,
                  label: s.version,
                  value: AppConstants.appVersion,
                ),
                const Divider(height: 1),
                _AboutRow(
                  icon: Icons.cloud_off_rounded,
                  label: s.worksOffline,
                  value: s.worksOfflineValue,
                ),
                const Divider(height: 1),
                _AboutRow(
                  icon: Icons.pets_rounded,
                  label: s.noAds,
                  value: s.noAdsValue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<_Currency> _currencies = <_Currency>[
    _Currency(symbol: 'Rs', code: 'PKR', label: 'Pakistani Rupee', decimals: 0),
    _Currency(symbol: '₨', code: 'INR', label: 'Indian Rupee', decimals: 0),
    _Currency(symbol: r'$', code: 'USD', label: 'US Dollar', decimals: 2),
    _Currency(symbol: '£', code: 'GBP', label: 'Pound Sterling', decimals: 2),
    _Currency(symbol: '€', code: 'EUR', label: 'Euro', decimals: 2),
    _Currency(symbol: r'A$', code: 'AUD', label: 'Australian Dollar', decimals: 2),
    _Currency(symbol: 'د.إ', code: 'AED', label: 'UAE Dirham', decimals: 2),
  ];

  Future<void> _pickReminderHour(BuildContext context, SettingsProvider settings) async {
    final int picked = settings.preferences.dailyReminderHour;
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext _) => RadioGroup<int>(
        groupValue: picked,
        onChanged: (int? value) => Navigator.pop(context, value),
        child: SimpleDialog(
          title: const Text('Reminder time'),
          children: <Widget>[
            for (int hour = 0; hour < 24; hour++)
              RadioListTile<int>(
                value: hour,
                title: Text('${hour.toString().padLeft(2, '0')}:00'),
              ),
          ],
        ),
      ),
    );
    if (result != null) await settings.setReminderHour(result);
  }

  static const List<int> _idleOptions = <int>[1, 2, 5, 10, 15, 30];
  static String _idleLabel(int minutes) => minutes == 1 ? '1 minute' : '$minutes minutes';

  Future<void> _pickIdleTimeout(BuildContext context, SettingsProvider settings) async {
    final int picked = settings.preferences.lockTimeoutMinutes;
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext _) => RadioGroup<int>(
        groupValue: _idleOptions.contains(picked)
            ? picked
            : AppConstants.sessionIdleTimeout.inMinutes,
        onChanged: (int? value) => Navigator.pop(context, value),
        child: SimpleDialog(
          title: const Text('Lock after'),
          children: <Widget>[
            for (final int minutes in _idleOptions)
              RadioListTile<int>(
                value: minutes,
                title: Text(_idleLabel(minutes)),
              ),
          ],
        ),
      ),
    );
    if (result != null) await settings.setLockTimeout(result);
  }

  Future<void> _changePin(BuildContext context, AuthProvider auth, AppLocalizations s) async {
    final bool? changed = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => ChangePinDialog(s: s),
    );
    if (changed != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.pinUpdated)));
  }

  Future<void> _eraseAll(
    BuildContext context,
    SettingsProvider settings,
    AppLocalizations s,
  ) async {
    final CommitteeProvider committees = context.read<CommitteeProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext _) => _EraseAllDialog(s: s),
        ) ??
        false;
    if (!confirmed) return;
    final String? message = await settings.eraseAllCommittees();
    if (!context.mounted) return;
    await committees.load();
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message ?? s.done)));
  }

  Future<void> _deleteAccount(
    BuildContext context,
    AuthProvider auth,
    SettingsProvider settings,
    AppLocalizations s,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext _) => _DeleteAccountDialog(s: s),
        ) ??
        false;
    if (!confirmed) return;
    final bool deleted = await auth.deleteAccount();
    if (!context.mounted) return;
    if (!deleted) {
      messenger.showSnackBar(
        SnackBar(content: Text(auth.error ?? 'The account could not be deleted.')),
      );
      return;
    }
    await settings.resetPreferences();
    messenger.showSnackBar(SnackBar(content: Text(s.deleteAccount)));
  }
}

// ---------------------------------------------------------------------------
// Profile card
// ---------------------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.auth, required this.s});

  final AuthProvider auth;
  final AppLocalizations s;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(auth.fullName, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(auth.user?.phoneNumber ?? '', style: theme.textTheme.bodySmall),
                if (auth.isAuthenticated)
                  StatusChip(
                    label: s.accountVerified,
                    color: AppColors.success,
                    compact: true,
                    icon: Icons.verified_rounded,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.editProfile,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editProfile(context),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final TextEditingController name = TextEditingController(text: auth.user?.fullName ?? '');
    final TextEditingController phone = TextEditingController(text: auth.user?.phoneNumber ?? '');
    final TextEditingController email = TextEditingController(text: auth.user?.email ?? '');

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => AlertDialog(
        title: Text(s.editProfile),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: s.fullName),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.phoneOptional),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: s.emailAddress),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.save)),
        ],
      ),
    );

    final String nameValue = name.text.trim();
    final String phoneValue = phone.text.trim();
    final String emailValue = email.text.trim();
    name.dispose();
    phone.dispose();
    email.dispose();

    if (saved != true) return;
    try {
      await auth.updateProfile(fullName: nameValue, phoneNumber: phoneValue, email: emailValue);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

// ---------------------------------------------------------------------------
// About row
// ---------------------------------------------------------------------------

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Text(value, style: theme.textTheme.bodySmall),
    );
  }
}

// ---------------------------------------------------------------------------
// Currency model
// ---------------------------------------------------------------------------

class _Currency {
  const _Currency({
    required this.symbol,
    required this.code,
    required this.label,
    required this.decimals,
  });

  final String symbol;
  final String code;
  final String label;
  final int decimals;
}

// ---------------------------------------------------------------------------
// Change PIN dialog
// ---------------------------------------------------------------------------

class ChangePinDialog extends StatefulWidget {
  const ChangePinDialog({super.key, required this.s});

  final AppLocalizations s;

  @override
  State<ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<ChangePinDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations s = widget.s;
    return AlertDialog(
      title: Text(s.changePinTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _current,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: s.currentPin, counterText: ''),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _next,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: s.newPin, counterText: ''),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: s.confirmNewPin, counterText: ''),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(onPressed: _submit, child: Text(s.update)),
      ],
    );
  }

  Future<void> _submit() async {
    final AuthProvider auth = context.read<AuthProvider>();
    final NavigatorState navigator = Navigator.of(context);
    final bool ok = await auth.changePin(
      currentPin: _current.text,
      newPin: _next.text,
      confirmPin: _confirm.text,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop(true);
    } else {
      setState(() => _error = auth.error);
    }
  }
}

// ---------------------------------------------------------------------------
// Erase all committees dialog
// ---------------------------------------------------------------------------

class _EraseAllDialog extends StatefulWidget {
  const _EraseAllDialog({required this.s});

  final AppLocalizations s;

  @override
  State<_EraseAllDialog> createState() => _EraseAllDialogState();
}

class _EraseAllDialogState extends State<_EraseAllDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _armed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations s = widget.s;
    return AlertDialog(
      title: Text(s.deleteAllCommittees),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Every committee, member, payment and turn will be removed permanently. '
            'Type DELETE to confirm.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Type DELETE'),
            onChanged: (String value) => setState(() => _armed = value.trim() == 'DELETE'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _armed ? () => Navigator.pop(context, true) : null,
          child: Text(s.delete),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Delete account dialog
// ---------------------------------------------------------------------------

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.s});

  final AppLocalizations s;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _armed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations s = widget.s;
    return AlertDialog(
      title: Text(s.deleteAccount),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Your account, PIN and every committee, member and payment on this device '
            'will be removed permanently. This cannot be undone. Type DELETE to confirm.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Type DELETE'),
            onChanged: (String value) => setState(() => _armed = value.trim() == 'DELETE'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _armed ? () => Navigator.pop(context, true) : null,
          child: Text(s.delete),
        ),
      ],
    );
  }
}
