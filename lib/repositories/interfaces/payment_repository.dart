import '../../models/payment.dart';

/// Persistence contract for payments.
///
/// Note that it exposes *intent* (`markPaid`) rather than exposing SQL, so the
/// business rule about duplicate payments lives in the repository where it can
/// be protected by a database constraint.
abstract interface class PaymentRepository {
  Future<List<Payment>> getByCommittee(String committeeId);
  Future<List<Payment>> getByPeriod(String committeeId, int periodNumber);
  Future<List<Payment>> getByMember(String memberId);
  Future<Payment?> getById(String id);
  Future<Payment?> find(String committeeId, String memberId, int periodNumber);
  Future<String> insert(Payment payment);

  /// Bulk insert, used when the schedule for every member is generated.
  Future<void> insertAll(List<Payment> payments);
  Future<void> update(Payment payment);
  Future<void> markPaid(String paymentId, DateTime paidAt, {String? method, String? notes});
  Future<void> markUnpaid(String paymentId);
  Future<void> deleteById(String id);
  Future<void> deleteByCommittee(String committeeId);
  Future<double> sumPaid(String committeeId);
  Future<double> sumPending(String committeeId);
  Future<int> countPaid(String committeeId);
  Future<int> countPending(String committeeId);
  Future<int> countOverdue(String committeeId, DateTime asOf);
  Future<int> countPaidInPeriod(String committeeId, int periodNumber);
  Future<int> countPendingInPeriod(String committeeId, int periodNumber);

  /// How many payment rows exist for a period (i.e. how many members are due).
  Future<int> countByPeriod(String committeeId, int periodNumber);

  /// Money actually received for a period.
  Future<double> sumPaidInPeriod(String committeeId, int periodNumber);
  Future<int> countAll();
  Future<double> sumPaidAll();
  Future<int> countPendingAll();
  Future<int> countOverdueAll(DateTime asOf);
  Future<List<({int periodNumber, double total, DateTime dueDate})>> collectionByPeriod(
    String committeeId,
  );
  Future<List<({int periodNumber, double total, DateTime dueDate})>> collectionByPeriodAll();
}
