import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/validators.dart';
import '../../models/enums.dart';
import '../../providers/committee_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/committee_service.dart' show MemberDraft;
import '../../widgets/app_card.dart';

/// One member row being typed on the create screen.
class _MemberRow {
  String name = '';
  String phone = '';
}

/// Committee creation.
///
/// The two rules that define a bachat committee are *derived*, never typed:
///  - the number of periods always equals the number of members, and
///  - the pot handed over each period is `(members - 1) x contribution`: the
///    member collecting that period does not pay into it.
///
/// Showing those as live, non-editable read-outs means the user cannot create an
/// internally inconsistent committee in the first place — validation on submit is
/// the safety net, not the primary mechanism.
class CreateCommitteeScreen extends StatefulWidget {
  const CreateCommitteeScreen({super.key});

  @override
  State<CreateCommitteeScreen> createState() => _CreateCommitteeScreenState();
}

class _CreateCommitteeScreenState extends State<CreateCommitteeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController(text: '10000');

  final List<_MemberRow> _members = <_MemberRow>[_MemberRow(), _MemberRow(), _MemberRow()];

  PaymentFrequency _frequency = PaymentFrequency.monthly;
  DateTime _startDate = AppDateUtils.today;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  int get _memberCount => _members.length;

  double get _contribution => Validators.parseAmount(_amount.text);

  double get _poolPerTurn => _contribution * (_memberCount <= 1 ? 0 : _memberCount - 1);

  /// Everyone pays into every pot except their own turn, and the number of
  /// periods always equals the number of members, so the money moving through
  /// the committee per whole life is `contribution x (memberCount - 1) x
  /// durationPeriods` (= (memberCount - 1) times the pot).
  double get _totalCollection => _contribution * (_memberCount <= 1 ? 0 : _memberCount - 1) * _memberCount;

  /// The first payment is due in period 1, whose due date is the start date
  /// itself (see [PaymentFrequency.dueDateForPeriod]).
  DateTime get _nextDueDate => _frequency.dueDateForPeriod(1, _startDate);

  /// Member rows whose name is still blank are not real members yet.
  int get _filledCount => _members.where((_MemberRow m) => m.name.trim().isNotEmpty).length;

  void _addMember() {
    if (_memberCount >= AppConstants.maxCommitteeMembers) return;
    setState(() => _members.add(_MemberRow()));
  }

  void _removeMember(int index) {
    if (_memberCount <= AppConstants.minCommitteeMembers) return;
    setState(() => _members.removeAt(index));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'First collection date',
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _scrollToTop();
      return;
    }
    setState(() => _submitting = true);
    if (!mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final DashboardProvider dashboard = context.read<DashboardProvider>();

    try {
      await context.read<CommitteeProvider>().create(
        name: _name.text.trim(),
        description: _description.text.trim(),
        contributionAmount: _contribution,
        frequency: _frequency,
        startDate: _startDate,
        memberDrafts: _members
            .where((_MemberRow m) => m.name.trim().isNotEmpty)
            .map(
              (_MemberRow m) => MemberDraft(
                name: m.name.trim(),
                phoneNumber: m.phone.trim(),
                // The first member organises the committee.
                role: m == _members.first ? MemberRole.organizer : MemberRole.member,
              ),
            )
            .toList(growable: false),
      );
          unawaited(dashboard.load());
      if (!mounted) return;
      navigator.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  void _scrollToTop() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Please fix the highlighted fields.')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New committee')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              120,
            ),
            children: <Widget>[
              SectionLabel('The basics'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Committee name',
                  hintText: 'e.g. Office Bachat Committee',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: Validators.committeeName,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _description,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Anything the group should remember',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionLabel('Collection rules'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Contribution per member',
                  prefixText: '${CurrencyFormatter.symbol} ',
                  helperText: 'Collected from every member, except the one receiving that pot',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                validator: Validators.contributionAmount,
                // Recompute the pool read-outs as the user types.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<PaymentFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'How often',
                  prefixIcon: Icon(Icons.calendar_month_rounded),
                ),
                items: <DropdownMenuItem<PaymentFrequency>>[
                  for (final PaymentFrequency f in PaymentFrequency.values)
                    DropdownMenuItem<PaymentFrequency>(value: f, child: Text(f.label)),
                ],
                onChanged: (PaymentFrequency? value) {
                  if (value != null) setState(() => _frequency = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'First collection date',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(AppDateUtils.formatDayMonthYear(_startDate))),
                      const Icon(Icons.arrow_drop_down_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _CalculationSummary(
                memberCount: _memberCount,
                filledCount: _filledCount,
                contribution: _contribution,
                poolPerTurn: _poolPerTurn,
                totalCollection: _totalCollection,
                nextDue: _nextDueDate,
                frequency: _frequency,
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionLabel('Members ($_filledCount/$_memberCount named)'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The first name becomes the organiser. Order here is the collection order: '
                'each member skips paying in the period their own pot is collected.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              ..._members.asMap().entries.map(
                (MapEntry<int, _MemberRow> entry) => _MemberEditor(
                  index: entry.key,
                  row: entry.value,
                  isFirst: entry.key == 0,
                  canRemove: _memberCount > AppConstants.minCommitteeMembers,
                  onChanged: () => setState(() {}),
                  onRemove: () => _removeMember(entry.key),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _memberCount >= AppConstants.maxCommitteeMembers ? null : _addMember,
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Add another member'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: FilledButton(
            onPressed: _submitting || _filledCount < AppConstants.minCommitteeMembers
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text('Create committee with $_filledCount members'),
          ),
        ),
      ),
    );
  }
}

/// The live arithmetic preview.
class _CalculationSummary extends StatelessWidget {
  const _CalculationSummary({
    required this.memberCount,
    required this.filledCount,
    required this.contribution,
    required this.poolPerTurn,
    required this.totalCollection,
    required this.nextDue,
    required this.frequency,
  });

  final int memberCount;
  final int filledCount;
  final double contribution;
  final double poolPerTurn;
  final double totalCollection;
  final DateTime nextDue;
  final PaymentFrequency frequency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool ready = filledCount >= AppConstants.minCommitteeMembers && contribution > 0;

    return AppCard(
      borderColor: ready ? AppColors.brandTeal.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.calculate_outlined,
                size: 18,
                color: ready ? AppColors.brandTeal : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('What this committee will do', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _CalcRow(label: 'Duration', value: '$memberCount periods (one per member)'),
          _CalcRow(
            label: 'Each member pays',
            value: '${CurrencyFormatter.format(contribution)} ${frequency.label.toLowerCase()}',
          ),
          _CalcRow(
            label: 'Pot handed over each period',
            value:
                '${memberCount - 1} × ${CurrencyFormatter.format(contribution)} = ${CurrencyFormatter.format(poolPerTurn)}',
            highlight: true,
          ),
          _CalcRow(
            label: 'Total moving through the committee',
            value: CurrencyFormatter.format(totalCollection),
          ),
          _CalcRow(label: 'First due date', value: AppDateUtils.formatDayMonthYear(nextDue)),
          if (!ready) ...<Widget>[
            const Divider(height: AppSpacing.xl),
            Text(
              'Name at least ${AppConstants.minCommitteeMembers} members to continue.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  const _CalcRow({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 4, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: highlight
                  ? theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberEditor extends StatelessWidget {
  const _MemberEditor({
    required this.index,
    required this.row,
    required this.isFirst,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _MemberRow row;
  final bool isFirst;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg, right: AppSpacing.sm),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: isFirst ? scheme.primary : scheme.surfaceContainerHighest,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isFirst ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                TextFormField(
                  initialValue: row.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: isFirst ? 'Organiser name' : 'Member ${index + 1} name',
                    isDense: true,
                  ),
                  validator: (String? value) {
                    // Only rows the user has touched are validated, so a freshly
                    // added blank row is not an error until they try to submit.
                    if ((value ?? '').trim().isEmpty) return null;
                    return Validators.memberName(value);
                  },
                  onChanged: (String value) {
                    row.name = value;
                    onChanged();
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  initialValue: row.phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)', isDense: true),
                  validator: (String? value) => Validators.phoneNumber(value),
                  onChanged: (String value) => row.phone = value,
                ),
              ],
            ),
          ),
          if (canRemove)
            IconButton(
              tooltip: 'Remove member ${index + 1}',
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
