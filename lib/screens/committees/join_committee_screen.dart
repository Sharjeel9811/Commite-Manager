import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../di/service_locator.dart';
import '../../models/committee.dart';
import '../../models/enums.dart';
import '../../models/member.dart';
import '../../providers/committee_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/committee_service.dart' show MemberDraft;
import '../../services/join_code_service.dart';
import '../../widgets/app_card.dart';

/// Shown after a committee is created.
/// Displays the 6-char join code and lets the organiser copy/share it.
class ShareCodeScreen extends StatelessWidget {
  const ShareCodeScreen({
    required this.committee,
    required this.members,
    required this.code,
    required this.expiresAt,
    super.key,
  });

  final Committee committee;
  final List<Member> members;
  final String code;
  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Committee Created')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Success icon
                Align(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  committee.name,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Committee created successfully!',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Join code card
                AppCard(
                  borderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.share_rounded, size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Join Code / شمولیت کوڈ',
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        code,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 12,
                          color: theme.colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Valid for 7 days • ${members.length} member slots',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Code copied!')),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                final String msg =
                                    'Join my committee "${committee.name}" on Committee Manager!\n'
                                    'Code: $code\n'
                                    'کمیٹی کا نام: ${committee.name}\n'
                                    'کوڈ: $code';
                                Share.share(msg);
                              },
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  color: AppColors.info.withValues(alpha: 0.06),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.info, size: 18),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Share this code with your members. '
                          'They can enter it in the app to see the committee details.\n\n'
                          'یہ کوڈ اپنے اراکین کو دیں۔ وہ اسے ایپ میں درج کر کے کمیٹی کی تفصیلات دیکھ سکتے ہیں۔',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton(
                  onPressed: () => Navigator.of(context).popUntil(
                    (Route<dynamic> r) => r.isFirst,
                  ),
                  child: const Text('Go to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen flow for a member to enter a join code.
class JoinCommitteeScreen extends StatefulWidget {
  const JoinCommitteeScreen({super.key});

  @override
  State<JoinCommitteeScreen> createState() => _JoinCommitteeScreenState();
}

class _JoinCommitteeScreenState extends State<JoinCommitteeScreen> {
  final TextEditingController _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final String code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character code.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final JoinCodeService svc =
        ServiceLocator.instance.get<JoinCodeService>();
    final JoinResult result = await svc.joinWithCode(code);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.isSuccess) {
      setState(() => _error = result.error);
      return;
    }

    // Preview screen
    final bool? confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _JoinPreviewScreen(
          committee: result.committee!,
          members: result.members!,
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Import the committee locally
    await _importLocally(result.committee!, result.members!);
  }

  Future<void> _importLocally(
      Committee committee, List<Member> members) async {
    setState(() => _loading = true);

    try {
      final CommitteeProvider cp = context.read<CommitteeProvider>();
      // Create committee with the members from the join code
      await cp.create(
        name: '${committee.name} (Joined)',
        description: committee.description,
        contributionAmount: committee.contributionAmount,
        frequency: committee.frequency,
        startDate: committee.startDate,
        memberDrafts: members
            .map((Member m) => MemberDraft(
                  name: m.name,
                  phoneNumber: m.phoneNumber,
                  role: m.role,
                ))
            .toList(),
      );
      if (!mounted) return;
      await context.read<DashboardProvider>().load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Joined "${committee.name}" successfully! / کمیٹی میں شامل ہو گئے!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not save the committee: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Join a Committee')),
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
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Icon(
                        Icons.group_add_rounded,
                        size: 36,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Enter the 6-character code',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '۶ حرفی کوڈ درج کریں جو منتظم نے بھیجا ہو',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]')),
                      UpperCaseFormatter(),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'XXXXXX',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _loading ? null : _join(),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: _loading ? null : _join,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Join Committee / کمیٹی میں شامل ہوں'),
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

/// Shows committee details fetched from the join code before confirming.
class _JoinPreviewScreen extends StatelessWidget {
  const _JoinPreviewScreen({
    required this.committee,
    required this.members,
  });

  final Committee committee;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Committee Preview')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: <Widget>[
          Text(committee.name, style: theme.textTheme.headlineSmall),
          if (committee.description != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(committee.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              children: <Widget>[
                _Row('Contribution', 'Rs ${committee.contributionAmount.toStringAsFixed(0)} / ${committee.frequency.label}'),
                const Divider(height: 1),
                _Row('Members', '${committee.memberCount}'),
                const Divider(height: 1),
                _Row('Start date', committee.startDate.toString().substring(0, 10)),
                const Divider(height: 1),
                _Row('Duration', '${committee.durationPeriods} periods'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Members', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final Member m in members)
            AppCard(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      m.initials,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(m.name, style: theme.textTheme.titleSmall),
                        if (m.phoneNumber != null)
                          Text(m.phoneNumber!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (m.isOrganizer)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandAmber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('Organiser',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.brandAmber)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join This Committee / اس کمیٹی میں شامل ہوں'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
              child: Text(label, style: theme.textTheme.bodySmall)),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Formats input to uppercase as the user types.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue _, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

// Minimal Share shim so the file compiles without share_plus
class Share {
  static void share(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }
}
