import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/committee.dart';
import '../../models/enums.dart';
import '../../models/statistics.dart';
import '../../providers/auth_provider.dart';
import '../../providers/committee_provider.dart' show AsyncValue;
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/committee_service.dart' show UpcomingDeadline;
import '../../widgets/app_card.dart';
import '../../widgets/entity_tiles.dart';
import '../../widgets/state_views.dart';

/// The home screen: a morning greeting, the money position, the next deadline and
/// a short list of active committees.
///
/// It reads from [DashboardProvider] only. Notably it does **not** talk to
/// [CommitteeProvider], even though both need committee data — separate read
/// models keep a search keystroke in the committees tab from rebuilding the
/// dashboard's charts.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DashboardProvider dashboard = context.watch<DashboardProvider>();
    final AsyncValue<DashboardStats> state = dashboard.state;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: dashboard.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: theme.scaffoldBackgroundColor,
                titleSpacing: AppSpacing.page,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      dashboard.greeting,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      context.select<AuthProvider, String>((AuthProvider p) => p.fullName),
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                actions: <Widget>[
                  const _ThemeToggleButton(),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
              if (state.isLoading && state.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: LoadingState())
              else if (state.hasError && state.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(message: state.error!, onRetry: dashboard.load),
                )
              else if (state.isReady)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    0,
                    AppSpacing.page,
                    AppSpacing.xxxl,
                  ),
                  sliver: SliverList.list(
                    children: <Widget>[
                      _MoneyHero(stats: dashboard.stats!),
                      const SizedBox(height: AppSpacing.lg),
                      _NextDeadlineCard(dashboard: dashboard),
                      const SizedBox(height: AppSpacing.lg),
                      _StatsGrid(stats: dashboard.stats!),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionHeader(
                        title: 'Active committees',
                        actionLabel: 'See all',
                        onAction: () => Navigator.of(context).pushNamed(AppRoutes.committees),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (dashboard.activeCommittees.isEmpty)
                        AppCard(
                          onTap: () => Navigator.of(context).pushNamed(AppRoutes.createCommittee),
                          child: Row(
                            children: <Widget>[
                              const AppIconBadge(icon: Icons.add_circle_outline_rounded),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  'Create your first committee to start collecting.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        )
                      else
                        ...dashboard.activeCommittees.map(
                          (Committee c) => CommitteeTile(
                            committee: c,
                            onTap: () =>
                                Navigator.of(context)
                                    .pushNamed(AppRoutes.committeeDetails, arguments: c.id),
                          ),
                        ),
                      if (dashboard.stats!.recentPayments.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        const _SectionHeader(title: 'Recent collections'),
                        const SizedBox(height: AppSpacing.md),
                        _RecentPaymentsCard(periods: dashboard.stats!.recentPayments),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gradient hero: collected vs outstanding across every committee.
class _MoneyHero extends StatelessWidget {
  const _MoneyHero({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progress = stats.totalCollected + stats.totalPending == 0
        ? 0
        : stats.totalCollected / (stats.totalCollected + stats.totalPending);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandIndigo.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.account_balance_wallet_outlined, size: 16, color: Colors.white70),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Collected so far',
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormatter.format(stats.totalCollected),
              style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _HeroStat(
                  label: 'Outstanding',
                  value: CurrencyFormatter.format(stats.totalPending),
                ),
              ),
              Container(width: 1, height: 30, color: Colors.white24),
              Expanded(
                child: _HeroStat(label: 'Committees', value: '${stats.totalCommittees}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The next due date, with an urgency colour.
class _NextDeadlineCard extends StatelessWidget {
  const _NextDeadlineCard({required this.dashboard});

  final DashboardProvider dashboard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UpcomingDeadline? deadline = dashboard.deadline;
    // Urgency comes from the deadline's own flags, never from re-reading the
    // headline string — a labelled label breaks the moment the wording changes.
    final bool urgent = deadline?.isOverdue == true || deadline?.isToday == true;
    final Color accent = urgent ? AppColors.danger : AppColors.brandAmber;

    return AppCard(
      onTap: deadline == null
          ? null
          : () =>
                Navigator.of(context)
                    .pushNamed(AppRoutes.committeeDetails, arguments: deadline.committee.id),
      child: Row(
        children: <Widget>[
          AppIconBadge(
            icon: deadline == null ? Icons.task_alt_rounded : Icons.event_rounded,
            background: accent.withValues(alpha: 0.12),
            foreground: accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  dashboard.deadlineHeadline,
                  style: theme.textTheme.titleSmall?.copyWith(color: urgent ? accent : null),
                ),
                const SizedBox(height: 2),
                Text(dashboard.deadlineSubtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (deadline != null)
            Text(
              dashboard.deadlineDateLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: StatTile(
                label: 'Members',
                value: '${stats.totalMembers}',
                icon: Icons.people_alt_rounded,
                tint: AppColors.info,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
                label: 'Turns done',
                value: '${stats.completedTurns}/${stats.totalTurns}',
                icon: Icons.swap_horiz_rounded,
                tint: AppColors.brandTeal,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: StatTile(
                label: 'Pending',
                value: '${stats.pendingPaymentCount}',
                icon: Icons.hourglass_bottom_rounded,
                tint: stats.pendingPaymentCount > 0 ? AppColors.warning : AppColors.success,
                caption: stats.overduePaymentCount > 0
                    ? '${stats.overduePaymentCount} overdue'
                    : (stats.dueSoonPaymentCount > 0
                          ? '${stats.dueSoonPaymentCount} due soon'
                          : null),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
                label: 'Completed',
                value: '${stats.completedCommittees}',
                icon: Icons.verified_rounded,
                tint: AppColors.success,
                caption: '${stats.activeCommittees} active',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentPaymentsCard extends StatelessWidget {
  const _RecentPaymentsCard({required this.periods});

  final List<PeriodCollection> periods;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < periods.length && i < 5; i++) ...<Widget>[
            if (i > 0) const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            ListTile(
              dense: true,
              leading: AppIconBadge(
                icon: periods[i].isComplete ? Icons.check_rounded : Icons.schedule_rounded,
                size: 38,
                background: (periods[i].isComplete ? AppColors.success : AppColors.warning)
                    .withValues(alpha: 0.12),
                foreground: periods[i].isComplete ? AppColors.success : AppColors.warning,
              ),
              title: Text(periods[i].committeeName, style: theme.textTheme.titleSmall),
              subtitle: Text(
                '${periods[i].label} • ${periods[i].paidCount}/${periods[i].totalCount} paid',
              ),
              trailing: Text(
                CurrencyFormatter.format(periods[i].collectedAmount),
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel ?? 'See all')),
      ],
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) {
    // The toggle must reflect what is actually on screen, not the stored
    // preference. When the preference is "follow system" and the device is in
    // dark mode the app shows dark, so `preference == dark` would be false and
    // the first tap would re-select dark — an invisible off-by-one press.
    // Reading the resolved brightness makes the first tap flip correctly.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light' : 'Switch to dark',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => context.read<SettingsProvider>().setTheme(
        isDark ? AppThemePreference.light : AppThemePreference.dark,
      ),
    );
  }
}
