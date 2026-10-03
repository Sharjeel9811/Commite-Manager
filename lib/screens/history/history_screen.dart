import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/statistics.dart';
import '../../providers/history_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_views.dart';

/// A chronological log of finished periods.
///
/// History is deliberately append-only from the user's point of view: nothing
/// here can be edited, because it is a record of what actually happened.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HistoryProvider history = context.watch<HistoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: history.load,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (history.all.isNotEmpty) _FilterRow(history: history),
          Expanded(child: _body(context, history, theme)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, HistoryProvider history, ThemeData theme) {
    if (history.state.isLoading && history.all.isEmpty) return const LoadingState();
    if (history.state.hasError && history.all.isEmpty) {
      return ErrorState(message: history.state.error!, onRetry: history.load);
    }
    if (history.all.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'No history yet',
        message:
            'Once a period is fully collected and the pot is handed over, it is recorded here '
            'so you always have a record of what happened.',
      );
    }

    final Map<String, List<PeriodCollection>> grouped = history.grouped;

    return RefreshIndicator(
      onRefresh: history.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: <Widget>[
          AppCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Periods logged',
                    value: '${history.all.length}',
                    icon: Icons.receipt_long_rounded,
                    tint: AppColors.info,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: StatTile(
                    label: 'Turns handed over',
                    value: '${history.completedTurns}',
                    icon: Icons.handshake_rounded,
                    tint: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final MapEntry<String, List<PeriodCollection>> entry in grouped.entries) ...<Widget>[
            SectionLabel(entry.key),
            const SizedBox(height: AppSpacing.md),
            for (final PeriodCollection period in entry.value)
              _HistoryTile(period: period, theme: theme),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.history});

  final HistoryProvider history;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.sm),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              label: const Text('All'),
              selected: history.committeeFilter == null,
              onSelected: (_) => history.filterBy(null),
            ),
          ),
          for (final String name in history.committeeNames)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                label: Text(name, overflow: TextOverflow.ellipsis),
                selected: history.committeeFilter == name,
                onSelected: (_) => history.filterBy(name),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.period, required this.theme});

  final PeriodCollection period;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color accent = period.isComplete ? AppColors.success : AppColors.neutral;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          AppIconBadge(
            icon: period.isComplete ? Icons.check_rounded : Icons.timelapse_rounded,
            background: accent.withValues(alpha: 0.12),
            foreground: accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(period.label, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Due ${AppDateUtils.formatDayMonthYear(period.dueDate)}'
                  '${period.completedAt != null ? ' • handed over ${AppDateUtils.formatDayMonth(period.completedAt!)}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                if (period.recipientName != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Received by ${period.recipientName}',
                    style: theme.textTheme.labelMedium?.copyWith(color: accent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                CurrencyFormatter.format(period.collectedAmount),
                style: theme.textTheme.titleSmall?.copyWith(color: accent),
              ),
              const SizedBox(height: 2),
              Text('${period.paidCount}/${period.totalCount}', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
