import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/locale_provider.dart';

/// The single source of truth for every user-visible string in the app.
///
/// Usage inside any widget:
/// ```dart
/// final s = AppLocalizations.of(context);
/// Text(s.appName)
/// ```
///
/// Adding a new string:
///   1. Add a getter to [AppLocalizations].
///   2. Add the English value to [_En].
///   3. Add the Urdu value to [_Ur].
///   Done — no codegen, no .arb files, no extra packages.
abstract class AppLocalizations {
  const AppLocalizations();

  /// Resolves the correct [AppLocalizations] instance from the widget tree.
  static AppLocalizations of(BuildContext context) {
    final AppLanguage lang = context.watch<LocaleProvider>().language;
    return lang == AppLanguage.urdu ? const _Ur() : const _En();
  }

  // ----------------------------------------------------------------- General
  String get appName;
  String get ok;
  String get cancel;
  String get save;
  String get delete;
  String get confirm;
  String get retry;
  String get loading;
  String get error;
  String get seeAll;
  String get search;
  String get close;
  String get update;
  String get add;
  String get edit;
  String get done;

  // ------------------------------------------------------------------- Auth
  String get createAccount;
  String get createAccountSubtitle;
  String get fullName;
  String get phoneOptional;
  String get phoneHelper;
  String get emailAddress;
  String get emailHelper;
  String get pin46;
  String get confirmPin;
  String get pinStorageNote;
  String get verifyAccount;
  String get verifySubtitle;
  String get verifyAndContinue;
  String get sendNewCode;
  String get nothingArrived;
  String get welcomeBack;
  String get enterPin;
  String get pinHint;
  String get unlock;
  String get useBiometrics;
  String get forgotPin;
  String get tooManyAttempts;
  String get lockedFor;
  String get verifyWithCode;
  String get lockoutNote;
  String get verifyIdentity;

  // --------------------------------------------------------------- Dashboard
  String get collectedSoFar;
  String get outstanding;
  String get committees;
  String get members;
  String get turnsDone;
  String get pending;
  String get completed;
  String get activeCommittees;
  String get recentCollections;
  String get createFirstCommittee;
  String get noDeadline;
  String get switchToLight;
  String get switchToDark;

  // --------------------------------------------------------------- Shell nav
  String get navHome;
  String get navCommittees;
  String get navHistory;
  String get navSettings;

  // --------------------------------------------------------------- Settings
  String get settings;
  String get appearance;
  String get currency;
  String get notifications;
  String get paymentReminders;
  String get paymentRemindersSubtitle;
  String get reminderTime;
  String get security;
  String get requirePin;
  String get requirePinSubtitle;
  String get lockAfter;
  String get unlockWithBiometrics;
  String get unlockWithBiometricsSubtitle;
  String get changePin;
  String get lockNow;
  String get verificationCodes;
  String get howCodesDelivered;
  String get data;
  String get sampleData;
  String get sampleDataSubtitle;
  String get resetPreferences;
  String get resetPreferencesSubtitle;
  String get deleteAllCommittees;
  String get deleteAllCommitteesSubtitle;
  String get deleteAccount;
  String get deleteAccountSubtitle;
  String get about;
  String get version;
  String get worksOffline;
  String get worksOfflineValue;
  String get noAds;
  String get noAdsValue;
  String get language;
  String get languageSubtitle;
  String get accountVerified;
  String get editProfile;
  String get pinUpdated;
  String get preferencesReset;
  String get changePinTitle;
  String get currentPin;
  String get newPin;
  String get confirmNewPin;

  // ------------------------------------------------------------ Committees
  String get createCommittee;
  String get committeeNameLabel;
  String get contributionAmount;
  String get duration;
  String get frequency;
  String get startDate;
  String get addMember;
  String get memberName;
  String get memberPhone;
  String get memberEmail;
  String get organizer;
  String get collectionOrder;
  String get turnNumber;

  // --------------------------------------------------------------- Payments
  String get markPaid;
  String get markUnpaid;
  String get amount;
  String get method;
  String get notes;
  String get dueDate;
  String get paidOn;
  String get overdue;
  String get dueSoon;

  // --------------------------------------------------------------- History
  String get history;
  String get allCommittees;
  String get paid;
  String get total;

  // ------------------------------------------------------------- Statistics
  String get statistics;
  String get collectionTrend;
  String get totalCollected;
  String get totalPending;

  // --------------------------------------------------------------- Errors
  String get pageNotFound;
  String get databaseError;

  // ---------------------------------------------------------- Committees list
  String get refresh;
  String get newCommittee;
  String get searchCommittees;
  String get allCount;
  String get activeCount;
  String get completedCount;
  String get archived;
  String get noMatches;
  String get noMatchesMsg;
  String get clearSearch;
  String get nothingHere;
  String get noCommitteesYet;
  String get noCommitteesMsg;
  String get createACommittee;

  // ------------------------------------------------- Create committee screen
  String get newCommitteeTitle;
  String get theBasics;
  String get committeeName;
  String get committeeNameHint;
  String get descriptionOptional;
  String get descriptionHint;
  String get collectionRules;
  String get contributionPerMember;
  String get contributionHelper;
  String get howOften;
  String get firstCollectionDate;
  String get whatThisWillDo;
  String get durationValue;
  String get eachMemberPays;
  String get potHandedOver;
  String get totalMoving;
  String get firstDueDate;
  String get nameMembersHint;
  String get membersSection;
  String get membersHint;
  String get addAnotherMember;
  String get organiserName;
  String get memberNName;
  String get phoneOptionalShort;
  String get createWith;
  String get fixFields;

  // --------------------------------------------------- Committee details
  String get overview;
  String get periods;
  String get potPerTurn;
  String get collected;
  String get turnsComplete;
  String get outstanding2;
  String get howItWorks;
  String get eachMemberReceives;
  String get runs;
  String get status;
  String get description;
  String get collect;
  String get changeCollectionOrder;
  String get archive;
  String get unarchive;
  String get deleteCommittee;
  String get deleteCommitteeConfirm;
  String get thisCannotBeUndone;
  String get running;
  String get periodsBehind;
  String get paymentsOverdue;
  String get noScheduleYet;
  String get noScheduleMsg;
  String get periodLabel;
  String get due;
  String get collects;
  String get complete;
  String get open;

  // ------------------------------------------------------- Members screen
  String get noMembersYet;
  String get noMembersMsg;
  String get addFirstMember;
  String get searchMembers;
  String get collectionOrderLocked;
  String get longPressToReorder;
  String get addMoreToReorder;
  String get collectionOrderUpdated;
  String get saveOrder;
  String get collectionOrderTitle;
  String get collectionOrderDesc;
  String get allPaidUp;
  String get rosterLocked;
  String get received;

  // ------------------------------------------------------- Payments screen
  String get allPaid;
  String get nothingToShow;
  String get nothingToShowMsg;
  String get howWasPaid;
  String get everyonePaid;
  String get markedPaid;
  String get markedUnpaid;
  String get outstandingPayments;

  // ------------------------------------------------------- History screen
  String get noHistoryYet;
  String get noHistoryMsg;
  String get periodsLogged;
  String get turnsHandedOver;
  String get handedOver;
  String get receivedBy;
  String get allFilter;

  // ---------------------------------------------------- Statistics screen
  String get turnsCompleted;
  String get membersReceivedPot;
  String get collectingNow;
  String get collectionByPeriod;
  String get nothingCollectedYet;
  String get peakPeriod;
  String get averagePeriod;
  String get active;
  String get doneLabel;
  String get awaiting;

  // --------------------------------------------------------------- Widgets
  String get loadingMsg;
  String get emptyTitle;
  String get errorRetry;
}

// =========================================================================
// English
// =========================================================================
class _En extends AppLocalizations {
  const _En();

  @override String get appName => 'Committee Manager';
  @override String get ok => 'OK';
  @override String get cancel => 'Cancel';
  @override String get save => 'Save';
  @override String get delete => 'Delete';
  @override String get confirm => 'Confirm';
  @override String get retry => 'Retry';
  @override String get loading => 'Loading…';
  @override String get error => 'Error';
  @override String get seeAll => 'See all';
  @override String get search => 'Search';
  @override String get close => 'Close';
  @override String get update => 'Update';
  @override String get add => 'Add';
  @override String get edit => 'Edit';
  @override String get done => 'Done';

  @override String get createAccount => 'Create your account';
  @override String get createAccountSubtitle => 'This account lives only on this device. No sign-up, no server.';
  @override String get fullName => 'Full name';
  @override String get phoneOptional => 'Phone number (optional)';
  @override String get phoneHelper => 'A contact detail for your committee, not for sign-in';
  @override String get emailAddress => 'Email address';
  @override String get emailHelper => 'Your verification code is sent here';
  @override String get pin46 => '4–6 digit PIN';
  @override String get confirmPin => 'Confirm PIN';
  @override String get pinStorageNote => 'Your PIN is salted and stretched before it is stored, so it cannot be read back out of the database.';
  @override String get verifyAccount => 'Verify your account';
  @override String get verifySubtitle => 'Enter the 6-digit code we sent to your email.';
  @override String get verifyAndContinue => 'Verify and continue';
  @override String get sendNewCode => 'Send a new code';
  @override String get nothingArrived => 'Nothing arrived? Check your spam folder and wait a minute before requesting a new code.';
  @override String get welcomeBack => 'Welcome back';
  @override String get enterPin => 'Enter your PIN to open';
  @override String get pinHint => 'Your PIN is between 4–6 digits. Press Unlock when done.';
  @override String get unlock => 'Unlock';
  @override String get useBiometrics => 'Use biometrics';
  @override String get forgotPin => 'Forgot your PIN?';
  @override String get tooManyAttempts => 'Too many attempts';
  @override String get lockedFor => 'Locked for';
  @override String get verifyWithCode => 'Verify with a code';
  @override String get lockoutNote => 'For your safety the PIN is locked after 5 wrong tries for 5 minutes.';
  @override String get verifyIdentity => 'Verify your identity';

  @override String get collectedSoFar => 'Collected so far';
  @override String get outstanding => 'Outstanding';
  @override String get committees => 'Committees';
  @override String get members => 'Members';
  @override String get turnsDone => 'Turns done';
  @override String get pending => 'Pending';
  @override String get completed => 'Completed';
  @override String get activeCommittees => 'Active committees';
  @override String get recentCollections => 'Recent collections';
  @override String get createFirstCommittee => 'Create your first committee to start collecting.';
  @override String get noDeadline => 'No upcoming deadline';
  @override String get switchToLight => 'Switch to light';
  @override String get switchToDark => 'Switch to dark';

  @override String get navHome => 'Home';
  @override String get navCommittees => 'Committees';
  @override String get navHistory => 'History';
  @override String get navSettings => 'Settings';

  @override String get settings => 'Settings';
  @override String get appearance => 'Appearance';
  @override String get currency => 'Currency';
  @override String get notifications => 'Notifications';
  @override String get paymentReminders => 'Payment reminders';
  @override String get paymentRemindersSubtitle => 'A nudge before each due date and each turn';
  @override String get reminderTime => 'Reminder time';
  @override String get security => 'Security';
  @override String get requirePin => 'Require PIN on open';
  @override String get requirePinSubtitle => 'Lock the app when you leave it';
  @override String get lockAfter => 'Lock after';
  @override String get unlockWithBiometrics => 'Unlock with biometrics';
  @override String get unlockWithBiometricsSubtitle => 'Use your fingerprint or face';
  @override String get changePin => 'Change PIN';
  @override String get lockNow => 'Lock now';
  @override String get verificationCodes => 'Verification codes';
  @override String get howCodesDelivered => 'How codes are delivered';
  @override String get data => 'Data';
  @override String get sampleData => 'Load sample data';
  @override String get sampleDataSubtitle => 'Three example committees to explore the app';
  @override String get resetPreferences => 'Reset preferences';
  @override String get resetPreferencesSubtitle => 'Restore theme, currency and notification defaults';
  @override String get deleteAllCommittees => 'Delete all committees';
  @override String get deleteAllCommitteesSubtitle => 'This cannot be undone';
  @override String get deleteAccount => 'Delete my account and all data';
  @override String get deleteAccountSubtitle => 'Removes your account, committees and any data on this device';
  @override String get about => 'About';
  @override String get version => 'Version';
  @override String get worksOffline => 'Works offline';
  @override String get worksOfflineValue => 'All data stays on this device';
  @override String get noAds => 'No accounts, no ads';
  @override String get noAdsValue => 'Nothing leaves your phone';
  @override String get language => 'Language';
  @override String get languageSubtitle => 'Choose app language / زبان منتخب کریں';
  @override String get accountVerified => 'Account verified';
  @override String get editProfile => 'Edit profile';
  @override String get pinUpdated => 'PIN updated';
  @override String get preferencesReset => 'Preferences reset';
  @override String get changePinTitle => 'Change PIN';
  @override String get currentPin => 'Current PIN';
  @override String get newPin => 'New PIN';
  @override String get confirmNewPin => 'Confirm new PIN';

  @override String get createCommittee => 'Create committee';
  @override String get committeeNameLabel => 'Committee name';
  @override String get contributionAmount => 'Contribution amount';
  @override String get duration => 'Duration';
  @override String get frequency => 'Frequency';
  @override String get startDate => 'Start date';
  @override String get addMember => 'Add member';
  @override String get memberName => 'Member name';
  @override String get memberPhone => 'Phone number';
  @override String get memberEmail => 'Email';
  @override String get organizer => 'Organizer';
  @override String get collectionOrder => 'Collection order';
  @override String get turnNumber => 'Turn number';

  @override String get markPaid => 'Mark paid';
  @override String get markUnpaid => 'Mark unpaid';
  @override String get amount => 'Amount';
  @override String get method => 'Method';
  @override String get notes => 'Notes';
  @override String get dueDate => 'Due date';
  @override String get paidOn => 'Paid on';
  @override String get overdue => 'Overdue';
  @override String get dueSoon => 'Due soon';

  @override String get history => 'History';
  @override String get allCommittees => 'All committees';
  @override String get paid => 'paid';
  @override String get total => 'total';

  @override String get statistics => 'Statistics';
  @override String get collectionTrend => 'Collection trend';
  @override String get totalCollected => 'Total collected';
  @override String get totalPending => 'Total pending';

  @override String get pageNotFound => 'That page does not exist.';
  @override String get databaseError => 'The local database could not be opened. Restart the app; if this keeps happening, reinstall it.';

  @override String get refresh => 'Refresh';
  @override String get newCommittee => 'New';
  @override String get searchCommittees => 'Search committees';
  @override String get allCount => 'All';
  @override String get activeCount => 'Active';
  @override String get completedCount => 'Completed';
  @override String get archived => 'Archived';
  @override String get noMatches => 'No matches';
  @override String get noMatchesMsg => 'Nothing matches your search. Try a different term.';
  @override String get clearSearch => 'Clear search';
  @override String get nothingHere => 'Nothing here';
  @override String get noCommitteesYet => 'No committees yet';
  @override String get noCommitteesMsg => 'A committee collects one fixed amount from every member each period and hands the whole pot to one member in turn.\n\nCreate your first one to get started.';
  @override String get createACommittee => 'Create a committee';

  @override String get newCommitteeTitle => 'New committee';
  @override String get theBasics => 'The basics';
  @override String get committeeName => 'Committee name';
  @override String get committeeNameHint => 'e.g. Office Bachat Committee';
  @override String get descriptionOptional => 'Description (optional)';
  @override String get descriptionHint => 'Anything the group should remember';
  @override String get collectionRules => 'Collection rules';
  @override String get contributionPerMember => 'Contribution per member';
  @override String get contributionHelper => 'Collected from every member, except the one receiving that pot';
  @override String get howOften => 'How often';
  @override String get firstCollectionDate => 'First collection date';
  @override String get whatThisWillDo => 'What this committee will do';
  @override String get durationValue => 'periods (one per member)';
  @override String get eachMemberPays => 'Each member pays';
  @override String get potHandedOver => 'Pot handed over each period';
  @override String get totalMoving => 'Total moving through the committee';
  @override String get firstDueDate => 'First due date';
  @override String get nameMembersHint => 'Name at least 2 members to continue.';
  @override String get membersSection => 'Members';
  @override String get membersHint => 'The first name becomes the organiser. Order here is the collection order.';
  @override String get addAnotherMember => 'Add another member';
  @override String get organiserName => 'Organiser name';
  @override String get memberNName => 'Member name';
  @override String get phoneOptionalShort => 'Phone (optional)';
  @override String get createWith => 'Create committee with';
  @override String get fixFields => 'Please fix the highlighted fields.';

  @override String get overview => 'Overview';
  @override String get periods => 'Periods';
  @override String get potPerTurn => 'Pot per turn';
  @override String get collected => 'Collected';
  @override String get turnsComplete => 'Turns complete';
  @override String get outstanding2 => 'Outstanding';
  @override String get howItWorks => 'How it works';
  @override String get eachMemberReceives => 'Each member receives';
  @override String get runs => 'Runs';
  @override String get status => 'Status';
  @override String get description => 'Description';
  @override String get collect => 'Collect';
  @override String get changeCollectionOrder => 'Change collection order';
  @override String get archive => 'Archive';
  @override String get unarchive => 'Unarchive';
  @override String get deleteCommittee => 'Delete committee';
  @override String get deleteCommitteeConfirm => 'This permanently removes the committee, its members, every payment and every turn. It cannot be undone.';
  @override String get thisCannotBeUndone => 'This cannot be undone';
  @override String get running => 'Running';
  @override String get periodsBehind => 'periods behind';
  @override String get paymentsOverdue => 'payments overdue';
  @override String get noScheduleYet => 'No schedule yet';
  @override String get noScheduleMsg => 'Periods appear once the committee has members.';
  @override String get periodLabel => 'Period';
  @override String get due => 'Due';
  @override String get collects => 'collects';
  @override String get complete => 'Complete';
  @override String get open => 'Open';

  @override String get noMembersYet => 'No members yet';
  @override String get noMembersMsg => 'Add the members of this committee in the order they should collect.';
  @override String get addFirstMember => 'Add the first member';
  @override String get searchMembers => 'Search members';
  @override String get collectionOrderLocked => 'Payments have been recorded, so the roster is locked.';
  @override String get longPressToReorder => 'Long-press a member and drag to change the order.';
  @override String get addMoreToReorder => 'Add more members to reorder the collection sequence.';
  @override String get collectionOrderUpdated => 'Collection order updated';
  @override String get saveOrder => 'Save order';
  @override String get collectionOrderTitle => 'Collection order';
  @override String get collectionOrderDesc => 'The member at the top collects first and skips paying in their own period.';
  @override String get allPaidUp => 'All paid up';
  @override String get rosterLocked => 'Roster locked';
  @override String get received => 'Received';

  @override String get allPaid => 'All paid';
  @override String get nothingToShow => 'Nothing to show';
  @override String get nothingToShowMsg => 'No members match this filter.';
  @override String get howWasPaid => 'How was it paid?';
  @override String get everyonePaid => 'Everyone in this period is marked as paid';
  @override String get markedPaid => 'marked as paid';
  @override String get markedUnpaid => 'marked as unpaid';
  @override String get outstandingPayments => 'Outstanding';

  @override String get noHistoryYet => 'No history yet';
  @override String get noHistoryMsg => 'Once a period is fully collected and the pot is handed over, it is recorded here.';
  @override String get periodsLogged => 'Periods logged';
  @override String get turnsHandedOver => 'Turns handed over';
  @override String get handedOver => 'handed over';
  @override String get receivedBy => 'Received by';
  @override String get allFilter => 'All';

  @override String get turnsCompleted => 'Turns completed';
  @override String get membersReceivedPot => 'members have received the pot';
  @override String get collectingNow => 'Collecting now';
  @override String get collectionByPeriod => 'Collection by period';
  @override String get nothingCollectedYet => 'Nothing collected yet';
  @override String get peakPeriod => 'Peak period';
  @override String get averagePeriod => 'Average period';
  @override String get active => 'active';
  @override String get doneLabel => 'done';
  @override String get awaiting => 'Awaiting';

  @override String get loadingMsg => 'Loading…';
  @override String get emptyTitle => 'Nothing here';
  @override String get errorRetry => 'Retry';
}

// =========================================================================
// Urdu
// =========================================================================
class _Ur extends AppLocalizations {
  const _Ur();

  @override String get appName => 'کمیٹی منیجر';
  @override String get ok => 'ٹھیک ہے';
  @override String get cancel => 'منسوخ';
  @override String get save => 'محفوظ کریں';
  @override String get delete => 'حذف کریں';
  @override String get confirm => 'تصدیق';
  @override String get retry => 'دوبارہ کوشش';
  @override String get loading => 'لوڈ ہو رہا ہے…';
  @override String get error => 'خرابی';
  @override String get seeAll => 'سب دیکھیں';
  @override String get search => 'تلاش';
  @override String get close => 'بند کریں';
  @override String get update => 'اپ ڈیٹ';
  @override String get add => 'شامل کریں';
  @override String get edit => 'ترمیم';
  @override String get done => 'مکمل';

  @override String get createAccount => 'اپنا اکاؤنٹ بنائیں';
  @override String get createAccountSubtitle => 'یہ اکاؤنٹ صرف اس ڈیوائس پر رہتا ہے۔ کوئی سائن اَپ نہیں، کوئی سرور نہیں۔';
  @override String get fullName => 'پورا نام';
  @override String get phoneOptional => 'فون نمبر (اختیاری)';
  @override String get phoneHelper => 'آپ کی کمیٹی کے لیے رابطہ کی تفصیل، سائن اِن کے لیے نہیں';
  @override String get emailAddress => 'ای میل پتہ';
  @override String get emailHelper => 'آپ کا تصدیقی کوڈ یہاں بھیجا جائے گا';
  @override String get pin46 => '۴ سے ۶ ہندسوں کا پِن';
  @override String get confirmPin => 'پِن کی تصدیق';
  @override String get pinStorageNote => 'آپ کا پِن ڈیٹابیس میں محفوظ ہونے سے پہلے انکرپٹ کیا جاتا ہے تاکہ اسے واپس نہ پڑھا جا سکے۔';
  @override String get verifyAccount => 'اپنا اکاؤنٹ تصدیق کریں';
  @override String get verifySubtitle => 'ہم نے آپ کی ای میل پر ۶ ہندسوں کا کوڈ بھیجا ہے۔ جاری رکھنے کے لیے درج کریں۔';
  @override String get verifyAndContinue => 'تصدیق کریں اور جاری رکھیں';
  @override String get sendNewCode => 'نیا کوڈ بھیجیں';
  @override String get nothingArrived => 'کچھ نہیں آیا؟ اپنے اسپیم فولڈر کو چیک کریں اور نیا کوڈ مانگنے سے پہلے ایک منٹ انتظار کریں۔';
  @override String get welcomeBack => 'خوش آمدید';
  @override String get enterPin => 'کمیٹیاں کھولنے کے لیے اپنا پِن درج کریں';
  @override String get pinHint => 'آپ کا پِن ۴ سے ۶ ہندسوں کا ہے۔ ان لاک دبائیں۔';
  @override String get unlock => 'ان لاک کریں';
  @override String get useBiometrics => 'بایومیٹرکس استعمال کریں';
  @override String get forgotPin => 'پِن بھول گئے؟';
  @override String get tooManyAttempts => 'بہت زیادہ کوششیں';
  @override String get lockedFor => 'بند ہے';
  @override String get verifyWithCode => 'کوڈ سے تصدیق کریں';
  @override String get lockoutNote => 'آپ کی حفاظت کے لیے ۵ غلط کوششوں کے بعد پِن ۵ منٹ کے لیے بند ہو جاتا ہے۔';
  @override String get verifyIdentity => 'اپنی شناخت تصدیق کریں';

  @override String get collectedSoFar => 'اب تک جمع';
  @override String get outstanding => 'باقی';
  @override String get committees => 'کمیٹیاں';
  @override String get members => 'اراکین';
  @override String get turnsDone => 'مکمل باریاں';
  @override String get pending => 'زیر التواء';
  @override String get completed => 'مکمل';
  @override String get activeCommittees => 'فعال کمیٹیاں';
  @override String get recentCollections => 'حالیہ وصولیاں';
  @override String get createFirstCommittee => 'جمع شروع کرنے کے لیے اپنی پہلی کمیٹی بنائیں۔';
  @override String get noDeadline => 'کوئی آنے والی تاریخ نہیں';
  @override String get switchToLight => 'لائٹ موڈ';
  @override String get switchToDark => 'ڈارک موڈ';

  @override String get navHome => 'ہوم';
  @override String get navCommittees => 'کمیٹیاں';
  @override String get navHistory => 'تاریخ';
  @override String get navSettings => 'ترتیبات';

  @override String get settings => 'ترتیبات';
  @override String get appearance => 'ظاہری شکل';
  @override String get currency => 'کرنسی';
  @override String get notifications => 'اطلاعات';
  @override String get paymentReminders => 'ادائیگی کی یاددہانیاں';
  @override String get paymentRemindersSubtitle => 'ہر مقررہ تاریخ اور باری سے پہلے اطلاع';
  @override String get reminderTime => 'یاددہانی کا وقت';
  @override String get security => 'سیکیورٹی';
  @override String get requirePin => 'کھولنے پر پِن درکار';
  @override String get requirePinSubtitle => 'چھوڑنے پر ایپ کو لاک کریں';
  @override String get lockAfter => 'لاک کریں';
  @override String get unlockWithBiometrics => 'بایومیٹرکس سے ان لاک';
  @override String get unlockWithBiometricsSubtitle => 'اپنی انگلی یا چہرہ استعمال کریں';
  @override String get changePin => 'پِن تبدیل کریں';
  @override String get lockNow => 'ابھی لاک کریں';
  @override String get verificationCodes => 'تصدیقی کوڈ';
  @override String get howCodesDelivered => 'کوڈ کیسے پہنچائے جاتے ہیں';
  @override String get data => 'ڈیٹا';
  @override String get sampleData => 'نمونہ ڈیٹا لوڈ کریں';
  @override String get sampleDataSubtitle => 'ایپ دریافت کرنے کے لیے تین مثالی کمیٹیاں';
  @override String get resetPreferences => 'ترجیحات دوبارہ سیٹ کریں';
  @override String get resetPreferencesSubtitle => 'تھیم، کرنسی اور اطلاعات کی ڈیفالٹ بحال کریں';
  @override String get deleteAllCommittees => 'تمام کمیٹیاں حذف کریں';
  @override String get deleteAllCommitteesSubtitle => 'یہ واپس نہیں ہو سکتا';
  @override String get deleteAccount => 'میرا اکاؤنٹ اور تمام ڈیٹا حذف کریں';
  @override String get deleteAccountSubtitle => 'آپ کا اکاؤنٹ، کمیٹیاں اور اس ڈیوائس کا تمام ڈیٹا ہٹا دیتا ہے';
  @override String get about => 'کے بارے میں';
  @override String get version => 'ورژن';
  @override String get worksOffline => 'آف لائن کام کرتا ہے';
  @override String get worksOfflineValue => 'تمام ڈیٹا اس ڈیوائس پر رہتا ہے';
  @override String get noAds => 'کوئی اکاؤنٹ نہیں، کوئی اشتہار نہیں';
  @override String get noAdsValue => 'کچھ بھی آپ کے فون سے نہیں جاتا';
  @override String get language => 'زبان';
  @override String get languageSubtitle => 'ایپ کی زبان منتخب کریں';
  @override String get accountVerified => 'اکاؤنٹ تصدیق شدہ';
  @override String get editProfile => 'پروفائل ترمیم کریں';
  @override String get pinUpdated => 'پِن اپ ڈیٹ ہو گیا';
  @override String get preferencesReset => 'ترجیحات دوبارہ سیٹ ہو گئیں';
  @override String get changePinTitle => 'پِن تبدیل کریں';
  @override String get currentPin => 'موجودہ پِن';
  @override String get newPin => 'نیا پِن';
  @override String get confirmNewPin => 'نئے پِن کی تصدیق';

  @override String get createCommittee => 'کمیٹی بنائیں';
  @override String get committeeNameLabel => 'کمیٹی کا نام';
  @override String get contributionAmount => 'چندہ کی رقم';
  @override String get duration => 'مدت';
  @override String get frequency => 'تعدد';
  @override String get startDate => 'آغاز کی تاریخ';
  @override String get addMember => 'رکن شامل کریں';
  @override String get memberName => 'رکن کا نام';
  @override String get memberPhone => 'فون نمبر';
  @override String get memberEmail => 'ای میل';
  @override String get organizer => 'منتظم';
  @override String get collectionOrder => 'وصولی کی ترتیب';
  @override String get turnNumber => 'باری نمبر';

  @override String get markPaid => 'ادا شدہ نشان لگائیں';
  @override String get markUnpaid => 'غیر ادا شدہ نشان لگائیں';
  @override String get amount => 'رقم';
  @override String get method => 'طریقہ';
  @override String get notes => 'نوٹس';
  @override String get dueDate => 'مقررہ تاریخ';
  @override String get paidOn => 'ادائیگی کی تاریخ';
  @override String get overdue => 'تاخیر';
  @override String get dueSoon => 'جلد واجب الادا';

  @override String get history => 'تاریخ';
  @override String get allCommittees => 'تمام کمیٹیاں';
  @override String get paid => 'ادا شدہ';
  @override String get total => 'کل';

  @override String get statistics => 'اعداد و شمار';
  @override String get collectionTrend => 'وصولی کا رجحان';
  @override String get totalCollected => 'کل جمع';
  @override String get totalPending => 'کل باقی';

  @override String get pageNotFound => 'یہ صفحہ موجود نہیں۔';
  @override String get databaseError => 'ڈیٹابیس نہیں کھل سکا۔ ایپ دوبارہ شروع کریں؛ اگر یہ ہوتا رہے تو دوبارہ انسٹال کریں۔';

  @override String get refresh => 'تازہ کریں';
  @override String get newCommittee => 'نئی';
  @override String get searchCommittees => 'کمیٹیاں تلاش کریں';
  @override String get allCount => 'تمام';
  @override String get activeCount => 'فعال';
  @override String get completedCount => 'مکمل';
  @override String get archived => 'محفوظ شدہ';
  @override String get noMatches => 'کوئی نتیجہ نہیں';
  @override String get noMatchesMsg => 'آپ کی تلاش سے کچھ نہیں ملا۔ مختلف الفاظ آزمائیں۔';
  @override String get clearSearch => 'تلاش صاف کریں';
  @override String get nothingHere => 'یہاں کچھ نہیں';
  @override String get noCommitteesYet => 'ابھی کوئی کمیٹی نہیں';
  @override String get noCommitteesMsg => 'کمیٹی میں ہر رکن ہر دور میں ایک مقررہ رقم جمع کرتا ہے اور پوری رقم باری باری ایک رکن کو دی جاتی ہے۔\n\nشروع کرنے کے لیے پہلی کمیٹی بنائیں۔';
  @override String get createACommittee => 'کمیٹی بنائیں';

  @override String get newCommitteeTitle => 'نئی کمیٹی';
  @override String get theBasics => 'بنیادی معلومات';
  @override String get committeeName => 'کمیٹی کا نام';
  @override String get committeeNameHint => 'مثلاً: دفتر بچت کمیٹی';
  @override String get descriptionOptional => 'تفصیل (اختیاری)';
  @override String get descriptionHint => 'گروپ کے لیے کوئی یاددہانی';
  @override String get collectionRules => 'وصولی کے اصول';
  @override String get contributionPerMember => 'ہر رکن کا چندہ';
  @override String get contributionHelper => 'ہر رکن سے جمع کیا جاتا ہے، سوائے اس کے جو اس دور میں وصول کرتا ہے';
  @override String get howOften => 'کتنے عرصے میں';
  @override String get firstCollectionDate => 'پہلی وصولی کی تاریخ';
  @override String get whatThisWillDo => 'یہ کمیٹی کیا کرے گی';
  @override String get durationValue => 'دور (ہر رکن کے لیے ایک)';
  @override String get eachMemberPays => 'ہر رکن ادا کرتا ہے';
  @override String get potHandedOver => 'ہر دور میں دی جانے والی رقم';
  @override String get totalMoving => 'کمیٹی میں کل رقم';
  @override String get firstDueDate => 'پہلی مقررہ تاریخ';
  @override String get nameMembersHint => 'جاری رکھنے کے لیے کم از کم ۲ ارکان کا نام درج کریں۔';
  @override String get membersSection => 'اراکین';
  @override String get membersHint => 'پہلا نام منتظم بنتا ہے۔ یہ ترتیب وصولی کی ترتیب ہے۔';
  @override String get addAnotherMember => 'ایک اور رکن شامل کریں';
  @override String get organiserName => 'منتظم کا نام';
  @override String get memberNName => 'رکن کا نام';
  @override String get phoneOptionalShort => 'فون (اختیاری)';
  @override String get createWith => 'کمیٹی بنائیں';
  @override String get fixFields => 'نشان زدہ خانے درست کریں۔';

  @override String get overview => 'جائزہ';
  @override String get periods => 'ادوار';
  @override String get potPerTurn => 'فی باری رقم';
  @override String get collected => 'جمع';
  @override String get turnsComplete => 'مکمل باریاں';
  @override String get outstanding2 => 'باقی';
  @override String get howItWorks => 'یہ کیسے کام کرتا ہے';
  @override String get eachMemberReceives => 'ہر رکن وصول کرتا ہے';
  @override String get runs => 'مدت';
  @override String get status => 'حالت';
  @override String get description => 'تفصیل';
  @override String get collect => 'وصول کریں';
  @override String get changeCollectionOrder => 'وصولی کی ترتیب تبدیل کریں';
  @override String get archive => 'محفوظ کریں';
  @override String get unarchive => 'بحال کریں';
  @override String get deleteCommittee => 'کمیٹی حذف کریں';
  @override String get deleteCommitteeConfirm => 'یہ کمیٹی، اس کے اراکین، تمام ادائیگیاں اور تمام باریاں مستقل طور پر حذف ہو جائیں گی۔ یہ واپس نہیں ہو سکتا۔';
  @override String get thisCannotBeUndone => 'یہ واپس نہیں ہو سکتا';
  @override String get running => 'چل رہی ہے';
  @override String get periodsBehind => 'ادوار پیچھے';
  @override String get paymentsOverdue => 'ادائیگیاں تاخیر میں';
  @override String get noScheduleYet => 'ابھی کوئی شیڈول نہیں';
  @override String get noScheduleMsg => 'اراکین شامل ہونے کے بعد ادوار نظر آئیں گے۔';
  @override String get periodLabel => 'دور';
  @override String get due => 'مقررہ تاریخ';
  @override String get collects => 'وصول کرتا ہے';
  @override String get complete => 'مکمل';
  @override String get open => 'کھلا';

  @override String get noMembersYet => 'ابھی کوئی رکن نہیں';
  @override String get noMembersMsg => 'اس کمیٹی کے اراکین وصولی کی ترتیب میں شامل کریں۔';
  @override String get addFirstMember => 'پہلا رکن شامل کریں';
  @override String get searchMembers => 'اراکین تلاش کریں';
  @override String get collectionOrderLocked => 'ادائیگیاں درج ہو چکی ہیں، اس لیے فہرست مقفل ہے۔';
  @override String get longPressToReorder => 'ترتیب بدلنے کے لیے کسی رکن کو دبا کر کھینچیں۔';
  @override String get addMoreToReorder => 'ترتیب بدلنے کے لیے مزید اراکین شامل کریں۔';
  @override String get collectionOrderUpdated => 'وصولی کی ترتیب اپ ڈیٹ ہو گئی';
  @override String get saveOrder => 'ترتیب محفوظ کریں';
  @override String get collectionOrderTitle => 'وصولی کی ترتیب';
  @override String get collectionOrderDesc => 'اوپر والا رکن پہلے وصول کرتا ہے اور اپنے دور میں ادائیگی سے مستثنیٰ ہوتا ہے۔';
  @override String get allPaidUp => 'سب ادا شدہ';
  @override String get rosterLocked => 'فہرست مقفل';
  @override String get received => 'وصول کیا';

  @override String get allPaid => 'سب ادا شدہ';
  @override String get nothingToShow => 'دکھانے کے لیے کچھ نہیں';
  @override String get nothingToShowMsg => 'کوئی رکن اس فلٹر سے نہیں ملتا۔';
  @override String get howWasPaid => 'ادائیگی کیسے ہوئی؟';
  @override String get everyonePaid => 'اس دور میں سب کو ادا شدہ نشان لگا دیا گیا';
  @override String get markedPaid => 'ادا شدہ نشان لگایا گیا';
  @override String get markedUnpaid => 'غیر ادا شدہ نشان لگایا گیا';
  @override String get outstandingPayments => 'باقی';

  @override String get noHistoryYet => 'ابھی کوئی تاریخ نہیں';
  @override String get noHistoryMsg => 'جب کوئی دور مکمل ہو جائے گا تو یہاں درج ہو گا۔';
  @override String get periodsLogged => 'درج ادوار';
  @override String get turnsHandedOver => 'مکمل باریاں';
  @override String get handedOver => 'حوالہ کیا';
  @override String get receivedBy => 'وصول کنندہ';
  @override String get allFilter => 'تمام';

  @override String get turnsCompleted => 'مکمل باریاں';
  @override String get membersReceivedPot => 'ارکان نے رقم وصول کی';
  @override String get collectingNow => 'ابھی وصول کر رہا ہے';
  @override String get collectionByPeriod => 'دور کے مطابق وصولی';
  @override String get nothingCollectedYet => 'ابھی کچھ جمع نہیں ہوا';
  @override String get peakPeriod => 'سب سے زیادہ دور';
  @override String get averagePeriod => 'اوسط دور';
  @override String get active => 'فعال';
  @override String get doneLabel => 'مکمل';
  @override String get awaiting => 'انتظار میں';

  @override String get loadingMsg => 'لوڈ ہو رہا ہے…';
  @override String get emptyTitle => 'یہاں کچھ نہیں';
  @override String get errorRetry => 'دوبارہ کوشش';
}
