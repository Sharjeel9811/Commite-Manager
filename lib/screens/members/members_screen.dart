import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/member.dart';
import '../../providers/committee_detail_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/edit_sheets.dart';
import '../../widgets/entity_tiles.dart';
import '../../widgets/state_views.dart';

/// The full roster for one committee, plus the collection-order editor.
///
/// The order shown here **is** the payout order, so it is draggable — but only
/// while it is safe. Once a payment exists the order is frozen, because changing
/// it would retroactively change who was due to receive the pot.
class MembersScreen extends StatefulWidget {
  const MembersScreen({required this.committeeId, super.key});

  final String committeeId;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CommitteeDetailProvider>().open(widget.committeeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommitteeDetailProvider detail = context.watch<CommitteeDetailProvider>();
    final String name = detail.committee?.name ?? 'Members';

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (detail.hasMembers)
            IconButton(
              tooltip: 'Change collection order',
              icon: const Icon(Icons.reorder_rounded),
              onPressed: !detail.canEditRoster ? null : () => _openReorder(context, detail),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: !detail.canEditRoster ? null : () => showMemberFormSheet(context, detail),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add'),
      ),
      body: _body(context, detail, theme),
    );
  }

  Widget _body(BuildContext context, CommitteeDetailProvider detail, ThemeData theme) {
    if (detail.isLoading && !detail.hasMembers) return const LoadingState();
    if (detail.error != null && !detail.hasMembers) {
      return ErrorState(message: detail.error!, onRetry: () => detail.open(widget.committeeId));
    }
    if (!detail.hasMembers) {
      return EmptyState(
        icon: Icons.person_add_alt_rounded,
        title: 'No members yet',
        message: 'Add the members of this committee in the order they should collect.',
        actionLabel: 'Add the first member',
        onAction: () => showMemberFormSheet(context, detail),
      );
    }

    final List<MemberContributionView> views = detail.contributions;

    final Widget rosterHeader = _rosterHeader(context, theme, detail, views);

    if (detail.canEditRoster) {
      return RefreshIndicator(
        onRefresh: detail.refresh,
        child: _ReorderableRoster(detail: detail, header: rosterHeader),
      );
    }

    return RefreshIndicator(
      onRefresh: detail.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, 96),
        children: <Widget>[
          rosterHeader,
          const SizedBox(height: AppSpacing.lg),
          for (final MemberContributionView view in views)
            _memberTile(context, theme, detail, view),
        ],
      ),
    );
  }

  Widget _rosterHeader(
    BuildContext context,
    ThemeData theme,
    CommitteeDetailProvider detail,
    List<MemberContributionView> views,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'Members',
                  value: '${views.length}',
                  icon: Icons.people_alt_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatTile(
                  label: 'All paid up',
                  value: '${views.where((MemberContributionView v) => v.isUpToDate).length}',
                  icon: Icons.verified_rounded,
                  tint: AppColors.success,
                ),
              ),
            ],
          ),
        ),
        if (!detail.canEditRoster) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: AppColors.warning.withValues(alpha: 0.06),
            borderColor: AppColors.warning.withValues(alpha: 0.4),
            child: Row(
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded, color: AppColors.warning),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Payments have been recorded, so the roster is locked.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SectionLabel('Collection order'),
        if (detail.canEditRoster && detail.hasMembers)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              detail.members.length > 1
                  ? 'Long-press a member and drag to change the order.'
                  : 'Add more members to reorder the collection sequence.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _memberTile(BuildContext context, ThemeData theme, CommitteeDetailProvider detail,
      MemberContributionView view) {
    return MemberTile(
      member: view.member,
      leadingBadge: '${view.member.turnNumber}',
      subtitle:
          '${view.paidCount}/${view.totalDue} paid • ${CurrencyFormatter.format(view.amountPaid)}'
          '${view.hasReceivedTurn ? ' • received ${AppDateUtils.formatCompact(view.receivedAt!)}' : ''}',
      trailing: view.hasReceivedTurn
          ? const StatusChip(label: 'Received', color: AppColors.success, compact: true)
          : (view.isUpToDate
                ? const StatusChip(label: 'Paid', color: AppColors.info, compact: true)
                : const StatusChip(label: 'Due', color: AppColors.warning, compact: true)),
      onTap: () => showMemberFormSheet(context, detail, existing: view.member),
    );
  }

  Future<void> _openReorder(BuildContext context, CommitteeDetailProvider detail) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final List<Member>? reordered = await showModalBottomSheet<List<Member>>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => _ReorderSheet(detail: detail),
    );
    if (reordered == null || !context.mounted) return;

    try {
      await detail.reorderTurns(reordered);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Collection order updated')));
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }
}

/// The roster as a long-press-draggable list that commits each drop to the
/// provider immediately (no separate "save order" step).
///
/// Only rendered while the roster is editable, so the drags can never rewrite
/// money that has already moved.
class _ReorderableRoster extends StatefulWidget {
  const _ReorderableRoster({required this.detail, required this.header});

  final CommitteeDetailProvider detail;
  final Widget header;

  @override
  State<_ReorderableRoster> createState() => _ReorderableRosterState();
}

class _ReorderableRosterState extends State<_ReorderableRoster> {
  late List<MemberContributionView> _ordered = List<MemberContributionView>.of(
    widget.detail.contributions,
  );

  @override
  void didUpdateWidget(covariant _ReorderableRoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt whatever fresh order the provider now holds (e.g. after a payment
    // edit elsewhere reloaded the committee), keeping drags in sync.
    if (!_sameOrder(_ordered, widget.detail.contributions)) {
      _ordered = List<MemberContributionView>.of(widget.detail.contributions);
    }
  }

  bool _sameOrder(List<MemberContributionView> a, List<MemberContributionView> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].member.id != b[i].member.id) return false;
    }
    return true;
  }

  Future<void> _commit() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await widget.detail.reorderTurns(<Member>[for (final view in _ordered) view.member]);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Collection order updated')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final CommitteeDetailProvider detail = widget.detail;

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, 96),
      header: widget.header,
      itemCount: _ordered.length,
      onReorderItem: (int oldIndex, int newIndex) async {
        setState(() {
          _ordered.insert(newIndex, _ordered.removeAt(oldIndex));
        });
        await _commit();
      },
      itemBuilder: (BuildContext context, int index) {
        final MemberContributionView view = _ordered[index];
        return MemberTile(
          key: ValueKey<String>(view.member.id),
          member: view.member,
          leadingBadge: '${view.member.turnNumber}',
          subtitle:
              '${view.paidCount}/${view.totalDue} paid • ${CurrencyFormatter.format(view.amountPaid)}'
              '${view.hasReceivedTurn ? ' • received ${AppDateUtils.formatCompact(view.receivedAt!)}' : ''}',
          trailing: view.hasReceivedTurn
              ? const StatusChip(label: 'Received', color: AppColors.success, compact: true)
              : (view.isUpToDate
                    ? const StatusChip(label: 'Paid', color: AppColors.info, compact: true)
                    : const StatusChip(label: 'Due', color: AppColors.warning, compact: true)),
          onTap: () => showMemberFormSheet(context, detail, existing: view.member),
        );
      },
    );
  }
}

/// Drag-to-reorder the payout sequence.
///
/// The user manipulates a plain `List<Member>` locally and only commits on save,
/// so dragging is instant and a cancelled sheet costs nothing.
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.detail});

  final CommitteeDetailProvider detail;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final List<Member> _ordered = List<Member>.of(widget.detail.members)
    ..sort((Member a, Member b) => a.turnNumber.compareTo(b.turnNumber));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Collection order', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The member at the top collects first and skips paying in their own '
                    'period. Everyone else pays the same amount, so the order decides '
                    'who skips when.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: controller,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                itemCount: _ordered.length,
                onReorderItem: (int oldIndex, int newIndex) {
                  setState(() {
                    _ordered.insert(newIndex, _ordered.removeAt(oldIndex));
                  });
                },
                itemBuilder: (BuildContext context, int index) {
                  final Member member = _ordered[index];
                  return Padding(
                    key: ValueKey<String>(member.id),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: Text(member.name, style: theme.textTheme.titleSmall)),
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle_rounded),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _ordered),
                  child: const Text('Save order'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
