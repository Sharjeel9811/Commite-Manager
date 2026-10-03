import '../../models/payment_schedule.dart';

/// Persistence contract for collection periods.
abstract interface class ScheduleRepository {
  Future<List<PaymentSchedule>> getByCommittee(String committeeId);
  Future<PaymentSchedule?> getByPeriod(String committeeId, int periodNumber);
  Future<PaymentSchedule?> getById(String id);
  Future<void> insertAll(List<PaymentSchedule> schedules);
  Future<void> closePeriod(String scheduleId);
  Future<void> reopenPeriod(String scheduleId);
  Future<PaymentSchedule?> getNextOpen(String committeeId, DateTime asOf);
  Future<void> deleteByCommittee(String committeeId);
  Future<int> countByCommittee(String committeeId);
}
