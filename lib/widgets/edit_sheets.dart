import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/validators.dart';
import '../../models/committee.dart';
import '../../models/enums.dart';
import '../../models/member.dart';
import '../../providers/committee_detail_provider.dart';
import '../../widgets/app_card.dart';

/// Add or edit a member.
///
/// A sheet rather than a full screen because it is always a short, focused task
/// on top of context the user can still see.
class MemberFormSheet extends StatefulWidget {
  const MemberFormSheet({required this.detail, super.key, this.existing});

  final CommitteeDetailProvider detail;
  final Member? existing;

  @override
  State<MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<MemberFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phoneNumber ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  late MemberRole _role = widget.existing?.role ?? MemberRole.member;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    if (!mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      if (_isEdit) {
        await widget.detail.updateMember(
          memberId: widget.existing!.id,
          name: _name.text.trim(),
          phoneNumber: _phone.text.trim(),
          address: _address.text.trim(),
          notes: _notes.text.trim(),
          role: _role,
        );
      } else {
        await widget.detail.addMember(
          name: _name.text.trim(),
          phoneNumber: _phone.text.trim(),
          address: _address.text.trim(),
          notes: _notes.text.trim(),
          role: _role,
        );
      }
      if (!mounted) return;
      navigator.pop();
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _remove() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext _) => AlertDialog(
            title: Text('Remove ${widget.existing!.name}?'),
            content: const Text(
              'Their turn and payment rows are removed too. This cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await widget.detail.removeMember(widget.existing!.id);
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final CommitteeDetailProvider detail = widget.detail;
    // A member who has already been paid must stay frozen: changing the roster
    // under a recorded payment would silently rewrite history.
    final bool frozen = _isEdit && !detail.canEditRoster;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _isEdit ? 'Edit member' : 'Add a member',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _isEdit
                    ? 'Update the details for ${widget.existing!.name}.'
                    : 'They join at the end of the collection order.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (String? value) => Validators.memberName(value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (String? value) => Validators.phoneNumber(value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.sticky_note_2_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<MemberRole>(
                segments: const <ButtonSegment<MemberRole>>[
                  ButtonSegment<MemberRole>(value: MemberRole.member, label: Text('Member')),
                  ButtonSegment<MemberRole>(value: MemberRole.organizer, label: Text('Organiser')),
                ],
                selected: <MemberRole>{_role},
                onSelectionChanged: (Set<MemberRole> value) => setState(() => _role = value.first),
              ),
              if (frozen) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.lock_outline_rounded, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'This committee has recorded payments, so the roster is locked.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(_isEdit ? 'Save changes' : 'Add member'),
              ),
              if (_isEdit) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _busy ? null : _remove,
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('Remove member'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a stored amount for editing without changing its value.
///
/// `.round()` used to be used here, which turned a 10.50 contribution into "11"
/// for every 2-decimal currency. Saving then compared "11" against the
/// untouched 10.50 and wrongly reported the amount as changed, blocking a rename
/// because of a rounding artefact.
String _editableAmountText(double amount) {
  final double rounded = (amount * 100).round() / 100;
  return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : '$rounded';
}

/// Edit a committee's name, description or contribution amount.
class EditCommitteeSheet extends StatefulWidget {
  const EditCommitteeSheet({required this.committee, super.key});

  final Committee committee;

  @override
  State<EditCommitteeSheet> createState() => _EditCommitteeSheetState();
}

class _EditCommitteeSheetState extends State<EditCommitteeSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.committee.name);
  late final TextEditingController _description = TextEditingController(
    text: widget.committee.description ?? '',
  );
  late final TextEditingController _amount = TextEditingController(
    text: _editableAmountText(widget.committee.contributionAmount),
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Committee committee = widget.committee;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Edit committee', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Committee name'),
                validator: (String? value) => Validators.committeeName(value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _description,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
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
                ),
                validator: (String? value) {
                  final String? basic = Validators.contributionAmount(value);
                  if (basic != null) return basic;
                  // Changing the amount would change every unpaid row's expected
                  // value, so it is only allowed while nothing has been paid.
                  if (!committee.isEditable) {
                    return 'Payments have been recorded, so the amount is locked';
                  }
                  if (!Validators.isSameAmount(
                    Validators.parseAmount(value),
                    committee.contributionAmount,
                  )) {
                    return 'The amount cannot be changed once payments exist';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  final String description = _description.text.trim();
                  Navigator.pop(context, (
                    name: _name.text.trim(),
                    description: description.isEmpty ? null : description,
                    amount: Validators.parseAmount(_amount.text),
                  ));
                },
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrappers so the two sheets can be shown from a private helper function.
Future<void> showMemberFormSheet(
  BuildContext context,
  CommitteeDetailProvider detail, {
  Member? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (BuildContext _) => MemberFormSheet(detail: detail, existing: existing),
);

Future<({String name, String? description, double amount})?> showEditCommitteeSheet(
  BuildContext context,
  Committee committee,
) => showModalBottomSheet<({String name, String? description, double amount})>(
  context: context,
  isScrollControlled: true,
  builder: (BuildContext _) => EditCommitteeSheet(committee: committee),
);
