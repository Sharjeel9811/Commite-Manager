import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/committee.dart';
import '../../models/member.dart';
import '../../models/statistics.dart';
import '../../providers/committee_detail_provider.dart';
import '../../providers/committee_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/edit_sheets.dart';
import '../../widgets/entity_tiles.dart';
import '../../widgets/state_views.dart';

/// Everything about one committee, and the doorway to its members and payments.
///
/// It is a *host* for a tabbed body, so a single [CommitteeDetailProvider] load
/// serves the overview, the members list and the per-period collection view. That
/// avoids three screens each independently re-querying the same snapshot and
/// disagreeing about the numbers.
class CommitteeDetailsScreen extends StatefulWidget {
  const CommitteeDetailsScreen({required this.committeeId, super.key});

  final String committeeId;

  @override
  State<CommitteeDetailsScreen> createState() => _CommitteeDetailsScreenState();
}

class _CommitteeDetailsScreenState extends State<CommitteeDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommitteeDetailProvider>().open(widget.committeeId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CommitteeDetailProvider detail = context.watch<CommitteeDetailProvider>();
    final Committee? committee = detail.committee;

    if (detail.isLoading && committee == null) {
      return const Scaffold(body: LoadingState());
    }
    if (committee == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: detail.error ?? 'This committee could not be opened.',
          onRetry: () => detail.open(widget.committeeId),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(committee.name, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editCommittee(context, committee),
          ),
          PopupMenuButton<String>(
            onSelected: (String value) => _onMenu(value, committee),
            itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'reorder',
                enabled: detail.canEditRoster && committee.memberCount > 2,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.reorder_rounded),
                  title: Text('Change collection order'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'archive',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(committee.isActive ? 'Archive' : 'Unarchive'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: Text('Delete committee', style: TextStyle(color: AppColors.danger)),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'Overview'),
            Tab(text: 'Members'),
            Tab(text: 'Periods'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _OverviewTab(detail: detail),
          _MembersTab(detail: detail),
          _PeriodsTab(detail: detail),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value, Committee committee) async {
    // Everything that touches the widget tree is resolved *before* the first
    // await, so no `BuildContext` is ever used across an async gap.
    final CommitteeDetailProvider detail = context.read<CommitteeDetailProvider>();
    final CommitteeProvider committees = context.read<CommitteeProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    if (value == 'reorder') {
      await navigator.pushNamed(AppRoutes.members, arguments: committee.id);
      return;
    }
    if (value == 'archive') {
      await detail.archive(!committee.isActive);
      return;
    }
    if (value != 'delete') return;

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext _) => AlertDialog(
            title: Text('Delete ${committee.name}?'),
            content: const Text(
              'This permanently removes the committee, its members, every payment and every turn. '
              'It cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await committees.delete(committee.id);
      navigator.pop();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _editCommittee(BuildContext context, Committee committee) async {
    final CommitteeDetailProvider detail = context.read<CommitteeDetailProvider>();

    final ({String name, String? description, double amount})? result =
        await showEditCommitteeSheet(context, committee);
    if (result == null) return;

    try {
      if (result.name != committee.name || result.description != committee.description) {
        await detail.updateCommitteeDetails(result.name, result.description);
      }
      if (result.amount != committee.contributionAmount) {
        await detail.updateContributionAmount(result.amount);
      }
    } on AppException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

// ------------------------------------------------------------------- Overview

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail});

  final CommitteeDetailProvider detail;

  @override
  Widget build(BuildContext context) {
    final Committee committee = detail.committee!;
    final CommitteeStats? stats = detail.stats;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: detail.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'Pot per turn',
                  value: CurrencyFormatter.format(committee.totalPoolPerTurn),
                  icon: Icons.savings_outlined,
                  tint: AppColors.brandIndigo,
                  caption: detail.poolFormula,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatTile(
                  label: 'Collected',
                  value: CurrencyFormatter.format(stats?.totalCollected ?? 0),
                  icon: Icons.trending_up_rounded,
                  tint: AppColors.success,
                  caption: '${stats?.collectionPercent.round() ?? 0}% of expected',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                AppProgressBar(
                  value: (stats?.turnProgressPercent ?? 0) / 100,
                  label:
                      'Turns: ${committee.completedTurns} of ${committee.durationPeriods} complete',
                ),
          if (stats?.isBehindSchedule ?? false) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: AppColors.warning.withValues(alpha: 0.06),
              borderColor: AppColors.warning.withValues(alpha: 0.4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.schedule_rounded, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      // The committee is still genuinely in the period whose
                      // money has not arrived yet, so say that plainly instead of
                      // quietly counting the calendar forward.
                      'Running ${stats!.periodsBehind} period'
                      '${stats.periodsBehind == 1 ? '' : 's'} behind - still on period '
                      '${stats.currentPeriod} of ${stats.totalPeriods}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: 'Members',
                        value: '${committee.memberCount}',
                        icon: Icons.people_alt_rounded,
                        tint: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: StatTile(
                        label: 'Outstanding',
                        value: CurrencyFormatter.format(stats?.totalPending ?? 0),
                        icon: Icons.money_off_csred_outlined,
                        tint: (stats?.totalPending ?? 0) > 0
                            ? AppColors.warning
                            : AppColors.success,
                        caption: '${stats?.pendingCount ?? 0} payments',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (stats?.hasOverdue ?? false) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: AppColors.danger.withValues(alpha: 0.06),
              borderColor: AppColors.danger.withValues(alpha: 0.4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '${stats!.overdueCount} payment${stats.overdueCount == 1 ? '' : 's'} overdue',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SectionLabel('How it works'),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _InfoRow(
                  icon: Icons.payments_outlined,
                  label: 'Each member pays',
                  value:
                      '${CurrencyFormatter.format(committee.contributionAmount)} ${committee.frequency.label.toLowerCase()}',
                ),
                const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                _InfoRow(
                  icon: Icons.rotate_right_rounded,
                  label: 'Each member receives',
                  value:
                      '${CurrencyFormatter.format(committee.totalPoolPerTurn)} (${committee.memberCount - 1} × ${CurrencyFormatter.format(committee.contributionAmount)})',
                ),
                const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                _InfoRow(
                  icon: Icons.event_available_rounded,
                  label: 'Runs',
                  value:
                      '${AppDateUtils.formatDayMonthYear(committee.startDate)} → ${AppDateUtils.formatDayMonthYear(committee.lastDueDate)}',
                ),
                const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                _InfoRow(
                  icon: committee.status.icon,
                  label: 'Status',
                  value: committee.status.label,
                  valueColor: committeeStatusColor(committee.status, scheme),
                ),
              ],
            ),
          ),
          if (committee.description != null && committee.description!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            SectionLabel('Description'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Text(committee.description!, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.payments, arguments: committee.id),
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('Collect'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.members, arguments: committee.id),
                  icon: const Icon(Icons.people_alt_rounded),
                  label: const Text('Members'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- Members

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.detail});

  final CommitteeDetailProvider detail;

  @override
  Widget build(BuildContext context) {
    if (!detail.hasMembers) {
      return EmptyState(
        icon: Icons.person_add_alt_rounded,
        title: 'No members yet',
        message: 'Add members to build the collection order.',
        actionLabel: 'Add a member',
        onAction: () => _showMemberSheet(context, detail),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.sm,
          ),
          child: TextField(
            onChanged: detail.searchMembers,
            decoration: const InputDecoration(
              hintText: 'Search members',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 88),
            children: <Widget>[
              for (final MemberContributionView view in detail.contributions)
                if (_matches(view)) _MemberRowTile(view: view, detail: detail),
              if (detail.visibleMembers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xxl),
                  child: Text('No members match your search.'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _matches(MemberContributionView view) {
    final String term = detail.memberQuery.trim().toLowerCase();
    if (term.isEmpty) return true;
    return view.member.name.toLowerCase().contains(term) ||
        (view.member.phoneNumber ?? '').contains(term);
  }
}

class _MemberRowTile extends StatelessWidget {
  const _MemberRowTile({required this.view, required this.detail});

  final MemberContributionView view;
  final CommitteeDetailProvider detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool received = view.hasReceivedTurn;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => _showMemberSheet(context, detail, existing: view.member),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            backgroundColor: received
                ? AppColors.success.withValues(alpha: 0.14)
                : theme.colorScheme.primaryContainer,
            child: Text(
              view.member.initials,
              style: theme.textTheme.labelLarge?.copyWith(
                color: received ? AppColors.success : theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        view.member.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (view.member.isOrganizer) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      const StatusChip(
                        label: 'Organiser',
                        color: AppColors.brandAmber,
                        compact: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                AppProgressBar(
                  value: view.percent / 100,
                  height: 6,
                  label:
                      '${view.paidCount}/${view.totalDue} paid • ${CurrencyFormatter.format(view.amountPaid)}',
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (received)
            const StatusChip(
              label: 'Received',
              color: AppColors.success,
              compact: true,
              icon: Icons.check_circle_outline_rounded,
            )
          else
            Text(
              '#${view.member.turnNumber}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Add or edit a member, also used by the standalone members screen.
Future<void> _showMemberSheet(
  BuildContext context,
  CommitteeDetailProvider detail, {
  Member? existing,
}) => showMemberFormSheet(context, detail, existing: existing);

// -------------------------------------------------------------------- Periods

class _PeriodsTab extends StatelessWidget {
  const _PeriodsTab({required this.detail});

  final CommitteeDetailProvider detail;

  @override
  Widget build(BuildContext context) {
    if (detail.periods.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_rounded,
        title: 'No schedule yet',
        message: 'Periods appear once the committee has members.',
      );
    }

    final List<PeriodView> periods = detail.periods;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.xxxl,
      ),
      itemCount: periods.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final PeriodView period = periods[index];
        return AppCard(
          onTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.payments, arguments: detail.committeeId),
          child: Row(
            children: <Widget>[
              AppIconBadge(
                icon: period.turnCompleted ? Icons.check_rounded : Icons.schedule_rounded,
                background: (period.turnCompleted ? AppColors.success : AppColors.brandAmber)
                    .withValues(alpha: 0.12),
                foreground: period.turnCompleted ? AppColors.success : AppColors.brandAmber,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Period ${period.periodNumber} • ${period.label}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due ${AppDateUtils.formatDayMonth(period.dueDate)}'
                      '${period.recipientName != null ? ' • ${period.recipientName} collects' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppProgressBar(
                      value: period.percent / 100,
                      height: 6,
                      label: '${period.paidCount}/${period.totalCount} paid',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                label: period.isComplete ? 'Complete' : 'Open',
                color: period.isComplete ? AppColors.success : AppColors.neutral,
                compact: true,
              ),
            ],
          ),
        );
      },
    );
  }
}
