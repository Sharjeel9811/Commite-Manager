import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/enums.dart';
import '../../providers/committee_detail_provider.dart';
import '../../providers/payment_provider.dart';
import '../../services/payment_service.dart' show PaymentRow;
import '../../widgets/app_card.dart';
import '../../widgets/state_views.dart';

/// Records who has paid for one period.
///
/// This is the highest-traffic screen in the app, so it is optimised for
/// one-thumb use: the period is a horizontal strip at the top, the list is
/// tap-to-toggle, and only the row being written shows a spinner — the rest of
/// the list stays interactive while a write is in flight.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    required this.committeeId,
    super.key,
    this.initialPeriod,
  });

  final String committeeId;
  final int? initialPeriod;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final CommitteeDetailProvider detail = context
          .read<CommitteeDetailProvider>();
      await detail.open(widget.committeeId);
      if (!mounted) return;

      final int period = widget.initialPeriod ?? detail.selectedPeriod;
      detail.selectPeriod(period);
      if (!mounted) return;
      await context.read<PaymentProvider>().open(
        committeeId: widget.committeeId,
        period: period,
      );
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Tap: always ask how the payment was made, then record it.
  /// This replaces the old "tap = cash, long-press = choose method" pattern
  /// which users never discovered.
  Future<void> _markPaid(PaymentProvider payments, PaymentRow row) async {
    final PaymentMethod? method = await _askMethod();
    if (!mounted || method == null) return;
    final String? proofPath = await _proofFor(method);
    if (!mounted || (method.requiresProof && proofPath == null)) return;
    await _recordPaid(payments, row, method: method, proofPath: proofPath);
  }

  /// Long-press: same as tap now — consistent behaviour.
  Future<void> _markPaidWithMethod(
    PaymentProvider payments,
    PaymentRow row,
  ) async {
    final PaymentMethod? method = await _askMethod();
    if (!mounted || method == null) return;
    final String? proofPath = await _proofFor(method);
    if (!mounted || (method.requiresProof && proofPath == null)) return;
    await _recordPaid(payments, row, method: method, proofPath: proofPath);
  }

  Future<void> _recordPaid(
    PaymentProvider payments,
    PaymentRow row, {
    required PaymentMethod? method,
    String? proofPath,
  }) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final CommitteeDetailProvider detail = context
        .read<CommitteeDetailProvider>();

    final String? error = await payments.markPaid(
      row.id,
      method: method,
      proofPath: proofPath,
    );
    if (!mounted) return;
    // The payment screen and the details screen show the same committee, so the
    // detail snapshot has to be refreshed too or they drift apart.
    await detail.refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              '${row.memberName} marked as paid (${method?.label ?? 'cash'})',
        ),
        backgroundColor: error == null ? AppColors.success : null,
      ),
    );
  }

  Future<String?> _proofFor(PaymentMethod method) async {
    if (!method.requiresProof) return null;
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return null;
    final Directory directory = await getApplicationDocumentsDirectory();
    final Directory proofs = Directory(
      p.join(directory.path, 'payment_proofs'),
    );
    await proofs.create(recursive: true);
    final String extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final String target = p.join(
      proofs.path,
      '${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await File(picked.path).copy(target);
    return target;
  }

  Future<void> _markUnpaid(PaymentProvider payments, PaymentRow row) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final CommitteeDetailProvider detail = context
        .read<CommitteeDetailProvider>();

    final String? error = await payments.markUnpaid(row.id);
    if (!mounted) return;
    await detail.refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? '${row.memberName} marked as unpaid'),
        backgroundColor: error == null ? AppColors.warning : null,
      ),
    );
  }

  Future<PaymentMethod?> _askMethod() async {
    return showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: <Widget>[
                  Text(
                    'How was it paid?  /  ادائیگی کا طریقہ',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            // Online payments
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                'Online / آن لائن',
                style: Theme.of(ctx).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(ctx).colorScheme.primary),
              ),
            ),
            for (final PaymentMethod m in <PaymentMethod>[
              PaymentMethod.easypaisa,
              PaymentMethod.jazzCash,
              PaymentMethod.nayaPay,
              PaymentMethod.sadaPay,
              PaymentMethod.hbl,
              PaymentMethod.meezan,
              PaymentMethod.ubl,
              PaymentMethod.mcb,
              PaymentMethod.askari,
              PaymentMethod.alfalah,
              PaymentMethod.bankTransfer,
            ])
              ListTile(
                leading: Text(m.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(m.label),
                dense: true,
                onTap: () => Navigator.pop(ctx, m),
              ),
            const Divider(),
            // Offline payments
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                'Offline / آف لائن',
                style: Theme.of(ctx).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(ctx).colorScheme.primary),
              ),
            ),
            for (final PaymentMethod m in <PaymentMethod>[
              PaymentMethod.cash,
              PaymentMethod.cheque,
              PaymentMethod.other,
            ])
              ListTile(
                leading: Text(m.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(m.label),
                dense: true,
                onTap: () => Navigator.pop(ctx, m),
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Cancel / منسوخ'),
              dense: true,
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _markAllPaid(PaymentProvider payments) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Mark everyone as paid?'),
        content: const Text(
          'This will mark every unpaid member in the selected period as paid. '
          'You can undo individual payments later.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Mark all paid'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final CommitteeDetailProvider detail = context
        .read<CommitteeDetailProvider>();

    final String? error = await payments.markWholePeriodPaid();
    if (!mounted) return;
    await detail.refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Everyone in this period is marked as paid'),
        backgroundColor: error == null ? AppColors.success : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommitteeDetailProvider detail = context
        .watch<CommitteeDetailProvider>();
    final PaymentProvider payments = context.watch<PaymentProvider>();
    final String committeeName = detail.committee?.name ?? 'Committee';

    return Scaffold(
      appBar: AppBar(
        title: Text(committeeName, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _PeriodStrip(detail: detail, payments: payments),
        ),
      ),
      floatingActionButton: payments.canMarkAllPaid
          ? FloatingActionButton.extended(
              onPressed: payments.isLoading
                  ? null
                  : () => _markAllPaid(payments),
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('All paid'),
            )
          : null,
      body: Column(
        children: <Widget>[
          _CollectionSummary(payments: payments),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: payments.search,
              decoration: InputDecoration(
                hintText: 'Search members',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: payments.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          payments.search('');
                        },
                      ),
              ),
            ),
          ),
          _FilterRow(payments: payments),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _list(context, payments, theme)),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    PaymentProvider payments,
    ThemeData theme,
  ) {
    if (payments.isLoading && payments.rows.isEmpty)
      return const LoadingState();
    if (payments.error != null && payments.rows.isEmpty) {
      return ErrorState(message: payments.error!, onRetry: payments.refresh);
    }

    final List<PaymentRow> rows = payments.visibleRows;
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing to show',
        message: 'No members match this filter.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        96,
      ),
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) {
        final PaymentRow row = rows[index];
        return _PaymentTile(
          row: row,
          busy: payments.isBusy(row.id),
          onTap: () => row.isPaid
              ? _markUnpaid(payments, row)
              : _markPaid(payments, row),
          onLongPress: row.isPaid
              ? null
              : () => _markPaidWithMethod(payments, row),
        );
      },
    );
  }
}

/// Horizontal strip of periods, with a dot showing each one's status.
class _PeriodStrip extends StatelessWidget {
  const _PeriodStrip({required this.detail, required this.payments});

  final CommitteeDetailProvider detail;
  final PaymentProvider payments;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (detail.periods.isEmpty) {
      return const SizedBox(height: 52);
    }

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page,
          vertical: AppSpacing.sm,
        ),
        itemCount: detail.periods.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final PeriodView period = detail.periods[index];
          final bool selected = period.periodNumber == payments.period;
          final Color accent = period.isComplete
              ? AppColors.success
              : AppColors.brandAmber;

          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            onSelected: (_) async {
              detail.selectPeriod(period.periodNumber);
              await payments.changePeriod(period.periodNumber);
            },
            avatar: period.isComplete
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: AppColors.success,
                  )
                : Icon(Icons.circle, size: 11, color: accent),
            label: Text('P${period.periodNumber}'),
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? theme.colorScheme.onSecondaryContainer : null,
            ),
          );
        },
      ),
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({required this.payments});

  final PaymentProvider payments;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        0,
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: 'Collected',
                  value: CurrencyFormatter.format(payments.collectedAmount),
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Outstanding',
                  value: CurrencyFormatter.format(payments.outstandingAmount),
                  color: payments.outstandingAmount > 0
                      ? AppColors.warning
                      : AppColors.neutral,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Paid',
                  value: '${payments.paidCount}/${payments.rows.length}',
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(
            value: payments.completionPercent / 100,
            label: payments.overdueCount > 0
                ? '${payments.overdueCount} overdue'
                : null,
            color: payments.overdueCount > 0
                ? AppColors.danger
                : AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.payments});

  final PaymentProvider payments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        children: <Widget>[
          for (final PaymentFilter filter in PaymentFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                label: Text(filter.label),
                selected: payments.filter == filter,
                onSelected: (_) => payments.changeFilter(filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// One member's row: name, amount, and a tap target that toggles paid/unpaid.
class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.row,
    required this.busy,
    required this.onTap,
    this.onLongPress,
  });

  final PaymentRow row;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool paid = row.isPaid;
    final Color accent = paid
        ? AppColors.success
        : (row.isSeverelyOverdue
              ? AppColors.brandRose
              : (row.isOverdue ? AppColors.danger : AppColors.warning));

    return AppCard(
      onTap: busy ? null : onTap,
      onLongPress: busy ? null : onLongPress,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: paid ? AppColors.success.withValues(alpha: 0.05) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: paid ? AppColors.success : Colors.transparent,
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: paid
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.memberName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (paid && row.proofPath != null)
                  TextButton.icon(
                    onPressed: () => _showProof(context, row.proofPath!),
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('View proof'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  paid
                      ? 'Paid ${AppDateUtils.formatDayMonth(row.paidDate ?? row.dueDate)}'
                            '${row.method != null ? ' • ${row.method!.label}' : ''}'
                      : (row.isOverdue
                            ? row.overdueLabel
                            : AppDateUtils.relativeDueText(row.dueDate)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: paid
                        ? AppColors.success
                        : (row.isOverdue
                              ? (row.isSeverelyOverdue
                                    ? AppColors.brandRose
                                    : AppColors.danger)
                              : null),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  CurrencyFormatter.format(row.amount),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                StatusChip(
                  label: row.statusLabel,
                  color: accent,
                  compact: true,
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showProof(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        child: InteractiveViewer(
          child: Image.file(
            File(path),
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Payment proof is no longer available on this device.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
