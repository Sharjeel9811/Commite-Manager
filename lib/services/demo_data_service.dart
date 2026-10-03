import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import 'committee_service.dart';
import 'payment_service.dart';
import 'reminder_service.dart';

/// Optional, clearly separated demo data.
///
/// Every committee it creates carries `isDemo = true`, which the UI shows as a
/// "Sample" chip, and it can be removed again with one tap without touching any
/// real committee.
class DemoDataService {
  const DemoDataService({
    required CommitteeService committeeService,
    required PaymentService paymentService,
    required ReminderService reminderService,
  }) : _committees = committeeService,
       _payments = paymentService,
       _reminders = reminderService;

  final CommitteeService _committees;
  final PaymentService _payments;
  final ReminderService _reminders;

  static const AppLogger _log = AppLogger('DemoDataService');

  /// Creates two example committees: one brand-new, one already running so the
  /// dashboard, history and charts are not empty.
  Future<int> loadSampleCommittees() async {
    final DateTime now = DateTime.now();

    final Committee fresh = await _committees.create(
      name: 'Friends Committee',
      description: 'A brand new committee, ready for its first collection.',
      contributionAmount: 10000,
      frequency: PaymentFrequency.monthly,
      startDate: now,
      memberDrafts: const <MemberDraft>[
        MemberDraft(name: 'Ali Raza', phoneNumber: '03001234567', role: MemberRole.organizer),
        MemberDraft(name: 'Ahmed Khan', phoneNumber: '03111234567'),
        MemberDraft(name: 'Usman Tariq', phoneNumber: '03221234567'),
        MemberDraft(name: 'Hamza Sheikh', phoneNumber: '03331234567'),
        MemberDraft(name: 'Bilal Ahmed', phoneNumber: '03441234567'),
      ],
      isDemo: true,
    );

    // A committee that started three months ago: the first turn is complete and
    // the second is collecting, so the app has something to display.
    final DateTime start = DateTime(now.year, now.month - 3, 1);
    final Committee running = await _committees.create(
      name: 'Office Committee',
      description: 'Monthly staff committee with one turn already handed over.',
      contributionAmount: 5000,
      frequency: PaymentFrequency.monthly,
      startDate: start,
      memberDrafts: const <MemberDraft>[
        MemberDraft(name: 'Zain Abbas', phoneNumber: '03007778881', role: MemberRole.organizer),
        MemberDraft(name: 'Faisal Iqbal', phoneNumber: '03007778882'),
        MemberDraft(name: 'Kashif Mehmood', phoneNumber: '03007778883'),
        MemberDraft(name: 'Danish Ali', phoneNumber: '03007778884'),
      ],
      isDemo: true,
    );

    await _seedProgress(running);
    await _reminders.rescheduleAll();
    _log.info('Sample committees created: ${fresh.name}, ${running.name}');
    return 2;
  }

  /// Marks period 1 fully paid and part of period 2, so history, progress bars
  /// and the statistics screen all have realistic data.
  Future<void> _seedProgress(Committee committee) async {
    final periodOne = await _payments.forPeriod(committee.id, 1);
    for (final payment in periodOne) {
      await _payments.markPaid(paymentId: payment.id);
    }
    final periodTwo = await _payments.forPeriod(committee.id, 2);
    // Everyone but the last member has paid in the current period.
    for (final payment in periodTwo.take(periodTwo.length - 1)) {
      await _payments.markPaid(paymentId: payment.id);
    }
  }

  /// Removes only the demo committees. Real data is never touched.
  Future<int> removeSampleCommittees() async {
    final List<Committee> all = await _committees.getAll();
    int removed = 0;
    for (final Committee committee in all) {
      if (committee.isDemo) {
        await _committees.delete(committee.id);
        removed++;
      }
    }
    if (removed > 0) {
      await _reminders.rescheduleAll();
      _log.info('Removed $removed sample committee(s)');
    }
    return removed;
  }

  /// Wipes every committee — used by "reset application data".
  Future<void> removeEverything() async {
    await _committees.deleteAll();
    await _reminders.rescheduleAll();
  }

  String get label => AppConstants.appName;
}
