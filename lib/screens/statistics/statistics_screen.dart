import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/statistics.dart';
import '../../providers/committee_provider.dart' show AsyncValue;
import '../../providers/statistics_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_views.dart';

/// Headline totals and a hand-drawn collection trend.
///
/// The chart is painted with a `CustomPainter` rather than a charting package:
/// it is a single bar series, and a ~60-line painter is smaller, has no
/// dependency, and can follow the app's own colours exactly.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StatisticsProvider stats = context.watch<StatisticsProvider>();
    final AsyncValue<DashboardStats> state = stats.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: stats.load,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: state.isLoading && stats.stats == null
          ? const LoadingState()
          : state.hasError && stats.stats == null
          ? ErrorState(message: state.error!, onRetry: stats.load)
          : RefreshIndicator(
              onRefresh: stats.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.lg,
                  AppSpacing.page,
                  AppSpacing.xxxl,
                ),
                children: <Widget>[
                  _TurnProgressCard(stats: stats.stats!, provider: stats),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: StatTile(
                          label: 'Committees',
                          value: '${stats.stats!.totalCommittees}',
                          icon: Icons.groups_rounded,
                          tint: AppColors.brandIndigo,
                          caption:
                              '${stats.stats!.activeCommittees} active • ${stats.stats!.completedCommittees} done',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: StatTile(
                          label: 'Members',
                          value: '${stats.stats!.totalMembers}',
                          icon: Icons.people_alt_rounded,
                          tint: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: StatTile(
                          label: 'Collected',
                          value: CurrencyFormatter.format(stats.stats!.totalCollected),
                          icon: Icons.trending_up_rounded,
                          tint: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: StatTile(
                          label: 'Awaiting',
                          value: CurrencyFormatter.format(stats.stats!.totalPending),
                          icon: Icons.hourglass_empty_rounded,
                          tint: stats.stats!.totalPending > 0
                              ? AppColors.warning
                              : AppColors.neutral,
                          caption: _awaitingCaption(stats.stats!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SectionLabel('Collection by period'),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: stats.trend.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            child: Center(
                              child: Text(
                                'Nothing collected yet',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          )
                        : _TrendChart(values: stats.trend, labels: stats.labels),
                  ),
                  if (stats.trend.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            label: 'Peak period',
                            value: CurrencyFormatter.format(stats.trendPeak),
                            icon: Icons.arrow_upward_rounded,
                            tint: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: StatTile(
                            label: 'Average period',
                            value: CurrencyFormatter.format(stats.trendAverage),
                            icon: Icons.show_chart_rounded,
                            tint: AppColors.brandTeal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _TurnProgressCard extends StatelessWidget {
  const _TurnProgressCard({required this.stats, required this.provider});

  final DashboardStats stats;
  final StatisticsProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Turns completed', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(
            value: stats.turnProgressPercent / 100,
            label: '${stats.completedTurns} of ${stats.totalTurns} members have received the pot',
            color: AppColors.brandTeal,
            height: 10,
          ),
          if (stats.currentRecipientName != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                const Icon(Icons.person_pin_circle_rounded, color: AppColors.brandIndigo),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Collecting now', style: theme.textTheme.labelSmall),
                      Text(stats.currentRecipientName!, style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(stats.currentTurnAmount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.brandIndigo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A short human line for the "Awaiting" tile: how many payments are pending,
/// with the overdue count first when there is one.
String _awaitingCaption(DashboardStats stats) {
  final String overdue = stats.overduePaymentCount > 0
      ? '${stats.overduePaymentCount} overdue'
      : '';
  final String soon = stats.dueSoonPaymentCount > 0
      ? '${stats.dueSoonPaymentCount} due soon'
      : '';
  final String extra = <String>[overdue, soon].where((String s) => s.isNotEmpty).join(' • ');
  return extra.isEmpty
      ? '${stats.pendingPaymentCount} payments'
      : '${stats.pendingPaymentCount} payments • $extra';
}

/// A minimal bar chart.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double peak = values.isEmpty ? 0 : values.reduce((double a, double b) => a > b ? a : b);

    return SizedBox(
      height: 180,
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarChartPainter(
                values: values,
                peak: peak,
                barColor: theme.colorScheme.primary,
                trackColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              for (int i = 0; i < values.length; i++)
                Expanded(
                  child: Text(
                    i < labels.length ? labels[i] : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.peak,
    required this.barColor,
    required this.trackColor,
  });

  final List<double> values;
  final double peak;
  final Color barColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final double slot = size.width / values.length;
    final double barWidth = (slot * 0.55).clamp(4.0, 28.0);
    final double radius = barWidth / 2;

    final Paint track = Paint()..color = trackColor;
    final Paint bar = Paint()..color = barColor;

    for (int i = 0; i < values.length; i++) {
      final double left = slot * i + (slot - barWidth) / 2;
      // Track first, so a zero-value period still shows its slot.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, barWidth, size.height),
          Radius.circular(radius),
        ),
        track,
      );
      if (peak <= 0 || values[i] <= 0) continue;
      final double height = (values[i] / peak) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          Radius.circular(radius),
        ),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values || old.barColor != barColor || old.peak != peak;
}
