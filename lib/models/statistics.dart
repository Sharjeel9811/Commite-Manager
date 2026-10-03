/// Read-only computed views used by the dashboard, the details screen and the
/// statistics screen.
///
/// These are *not* stored in the database. They are recomputed from the source
/// data by `PaymentCalculator` / `StatisticsService`, which guarantees the
/// numbers on screen can never disagree with the underlying rows.
library;

/// Everything the UI needs to draw one committee's numbers.
class CommitteeStats {
  const CommitteeStats({
    required this.committeeId,
    required this.totalMembers,
    required this.activeMembers,
    required this.contributionAmount,
    required this.expectedPool,
    required this.totalCollected,
    required this.totalPending,
    required this.paidCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.completedTurns,
    required this.totalTurns,
    required this.currentPeriod,
    required this.totalPeriods,
    this.expectedPeriod = 0,
    required this.currentRecipientName,
    required this.nextRecipientName,
    required this.nextDueDate,
    required this.startDate,
    required this.endDate,
  });

  final String committeeId;
  final int totalMembers;
  final int activeMembers;
  final double contributionAmount;

  /// memberCount x contributionAmount — what one member receives on their turn.
  final double expectedPool;

  final double totalCollected;
  final double totalPending;
  final int paidCount;
  final int pendingCount;
  final int overdueCount;

  final int completedTurns;
  final int totalTurns;

  /// The period actually being collected right now.
  ///
  /// This tracks [Committee.currentTurn], which only advances once every member
  /// has actually paid the previous period. It is deliberately *not* derived
  /// from the calendar: a committee that lapsed is still genuinely in period 1
  /// until the money arrives, and labelling that as "period 6" would contradict
  /// [currentRecipientName] and [nextDueDate], which both come from the same
  /// turn. See [expectedPeriod] for the calendar view.
  final int currentPeriod;
  final int totalPeriods;

  /// The period the calendar says we *should* be in, based on the start date.
  ///
  /// Only used to report lateness, never to name the recipient.
  final int expectedPeriod;

  /// How many periods behind the calendar this committee is running.
  /// 0 means it is on schedule (or ahead, which it cannot really be).
  int get periodsBehind => (expectedPeriod - currentPeriod).clamp(0, totalPeriods);

  /// True when the committee has missed its own schedule and the user should be
  /// told, rather than silently shown a period number that has moved on.
  bool get isBehindSchedule => periodsBehind > 0;

  final String? currentRecipientName;
  final String? nextRecipientName;
  final DateTime? nextDueDate;
  final DateTime startDate;
  final DateTime endDate;

  int get totalPayments => paidCount + pendingCount;

  int get remainingTurns => (totalTurns - completedTurns).clamp(0, totalTurns);

  /// 0.0 - 100.0 of all expected payments.
  double get collectionPercent => totalPayments == 0 ? 0 : (paidCount / totalPayments) * 100;

  /// 0.0 - 100.0 of the committee's lifetime.
  double get turnProgressPercent => totalTurns == 0 ? 0 : (completedTurns / totalTurns) * 100;

  /// Each member pays in every period except the one they collect, so the whole
  /// life total is `(totalMembers - 1) x totalPeriods x contributionAmount`.
  double get expectedTotalCollection =>
      contributionAmount * (totalMembers <= 1 ? 0 : totalMembers - 1) * totalPeriods;

  bool get isFullyCollected => pendingCount == 0 && totalPayments > 0;

  bool get hasOverdue => overdueCount > 0;
}

/// Aggregated numbers for the whole app.
class DashboardStats {
  const DashboardStats({
    required this.totalCommittees,
    required this.activeCommittees,
    required this.completedCommittees,
    required this.draftCommittees,
    required this.totalMembers,
    required this.totalCollected,
    required this.totalPending,
    required this.pendingPaymentCount,
    required this.overduePaymentCount,
    required this.completedTurns,
    required this.totalTurns,
    this.dueSoonPaymentCount = 0,
    this.nextDueDate,
    this.nextDueCommitteeName,
    this.currentRecipientName,
    this.currentRecipientCommittee,
    this.currentTurnAmount = 0,
    this.recentPayments = const <PeriodCollection>[],
    this.monthlyCollection = const <double>[],
    this.monthlyLabels = const <String>[],
  });

  final int totalCommittees;
  final int activeCommittees;
  final int completedCommittees;
  final int draftCommittees;
  final int totalMembers;

  final double totalCollected;
  final double totalPending;
  final int pendingPaymentCount;
  final int overduePaymentCount;
  final int dueSoonPaymentCount;

  final int completedTurns;
  final int totalTurns;

  final DateTime? nextDueDate;
  final String? nextDueCommitteeName;
  final String? currentRecipientName;
  final String? currentRecipientCommittee;
  final double currentTurnAmount;

  /// Completed periods, newest first — powers the dashboard "recent activity".
  final List<PeriodCollection> recentPayments;

  /// Collected amount for the last 6 periods — powers the trend chart.
  final List<double> monthlyCollection;
  final List<String> monthlyLabels;

  bool get hasCommittees => totalCommittees > 0;

  bool get hasPending => pendingPaymentCount > 0;

  int get remainingTurns => (totalTurns - completedTurns).clamp(0, totalTurns);

  double get turnProgressPercent => totalTurns == 0 ? 0 : (completedTurns / totalTurns) * 100;

  /// Money currently sitting in the pools.
  double get currentPool => totalCollected - totalPending < 0 ? 0 : totalCollected - totalPending;
}

/// One period of one committee, with its collection summary.
class PeriodCollection {
  const PeriodCollection({
    required this.committeeId,
    required this.committeeName,
    required this.periodNumber,
    required this.label,
    required this.dueDate,
    required this.expectedAmount,
    required this.collectedAmount,
    required this.paidCount,
    required this.totalCount,
    required this.recipientName,
    required this.turnStatus,
    this.isClosed = false,
    this.completedAt,
  });

  final String committeeId;
  final String committeeName;
  final int periodNumber;
  final String label;
  final DateTime dueDate;

  final double expectedAmount;
  final double collectedAmount;
  final int paidCount;
  final int totalCount;
  final String? recipientName;
  final String turnStatus;
  final bool isClosed;
  final DateTime? completedAt;

  int get pendingCount => (totalCount - paidCount).clamp(0, totalCount);

  bool get isComplete => totalCount > 0 && paidCount == totalCount;

  double get completionPercent => totalCount == 0 ? 0 : (paidCount / totalCount) * 100;

  double get outstandingAmount =>
      (expectedAmount - collectedAmount) < 0 ? 0 : expectedAmount - collectedAmount;
}

/// Per-member contribution summary.
class MemberContribution {
  const MemberContribution({
    required this.memberId,
    required this.name,
    required this.turnNumber,
    required this.paidCount,
    required this.pendingCount,
    required this.amountPaid,
    required this.hasReceivedTurn,
    this.receivedAt,
  });

  final String memberId;
  final String name;
  final int turnNumber;
  final int paidCount;
  final int pendingCount;
  final double amountPaid;
  final bool hasReceivedTurn;
  final DateTime? receivedAt;

  int get totalDue => paidCount + pendingCount;

  double get paymentPercent => totalDue == 0 ? 0 : (paidCount / totalDue) * 100;

  bool get isUpToDate => pendingCount == 0;
}
