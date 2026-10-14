# Committee Manager App

Committee Manager is an offline-first Flutter application for operating a
Bachat Committee, also known as a rotating savings group, ROSCA, or committee
savings group.

The app helps an organiser:

- create a committee and define its payment schedule;
- record members and their collection order;
- generate every expected payment row;
- mark contributions paid or undo an incorrectly recorded payment;
- identify the current collector and the next outstanding period;
- monitor pending, overdue, and severely overdue contributions;
- review member, period, and committee statistics;
- export/share a committee report; and
- protect financial history from accidental structural edits.

The primary local data store is SQLite. Core committee operations do not require
an internet connection. Email OTP verification is the exception: registration
uses the configured OTP provider to verify the user's email address.

---

## Contents

1. [Product workflow](#product-workflow)
2. [First launch and authentication](#first-launch-and-authentication)
3. [Application shell](#application-shell)
4. [Creating a committee](#creating-a-committee)
5. [Committee mathematics](#committee-mathematics)
6. [Generated schedule](#generated-schedule)
7. [Managing members](#managing-members)
8. [Recording payments](#recording-payments)
9. [Turn and committee state workflow](#turn-and-committee-state-workflow)
10. [Overdue workflow](#overdue-workflow)
11. [Editing and data-protection rules](#editing-and-data-protection-rules)
12. [Dashboard and statistics](#dashboard-and-statistics)
13. [History and reports](#history-and-reports)
14. [Notifications and reminders](#notifications-and-reminders)
15. [Settings and session security](#settings-and-session-security)
16. [Persistence and migrations](#persistence-and-migrations)
17. [Application architecture](#application-architecture)
18. [Important source locations](#important-source-locations)
19. [Local development](#local-development)
20. [Testing and verification](#testing-and-verification)
21. [Android builds and APK workflow](#android-builds-and-apk-workflow)
22. [Business assumptions](#business-assumptions)

---

## Product workflow

The complete user journey is:

```text
Install app
    |
    v
Register account -> email OTP -> create PIN
    |
    v
Unlock app
    |
    v
Dashboard
    |
    +--> Create committee
    |       |
    |       +--> enter committee details
    |       +--> enter at least two members
    |       +--> choose frequency and start date
    |       +--> accept terms
    |       +--> generate periods, turns, and payment rows
    |
    +--> Open committee
            |
            +--> review overview and current collector
            +--> manage members while payment history is empty
            +--> open a period
            +--> mark contributions paid
            +--> review completed and upcoming turns
            +--> inspect statistics/history/report
            +--> archive when appropriate
```

The organiser does not manually create payment rows or manually advance the
rotation. Those actions are derived from the committee definition and payment
state.

---

## First launch and authentication

### Registration

On a fresh installation:

1. The user opens the registration screen.
2. The user enters their name, email/phone details as requested, and a PIN.
3. The app validates the fields locally.
4. An email OTP challenge is sent through the configured OTP provider.
5. The user enters the OTP on the verification screen.
6. The challenge is checked and consumed.
7. The user reaches the authenticated application shell.

OTP challenges have an expiry and an attempt limit. Failed or expired
challenges do not leave a usable verification code behind.

### Login and lock screen

After registration, the local PIN is used to unlock the app. The PIN is stored
as a salted hash, never as plaintext. If biometric unlock is enabled and the
device supports it, the app can use the device biometric prompt.

The session guard monitors inactivity. When the configured idle timeout is
reached, the app returns to the lock screen. Logging out or forcing a lock also
returns to the lock screen.

### Auth states

The authentication gate selects the appropriate screen for the current state:

| State | Screen |
|---|---|
| Loading | Splash/loading state |
| Unauthenticated | Registration or login flow |
| OTP required | OTP verification screen |
| Authenticated but locked | Lock screen |
| Authenticated and unlocked | Main application shell |

---

## Application shell

The authenticated shell provides access to the main product areas:

- **Dashboard** - active committees, totals, current collection information,
  overdue counts, and reminders.
- **Committees** - list, search, filter, create, open, archive, and delete
  committees.
- **History** - completed collections and historical activity.
- **Statistics** - aggregate and committee-level financial progress.
- **Settings** - language, theme, notification, biometric, and session
  preferences.

Opening a committee loads one consistent bundle containing:

- committee header;
- ordered members;
- generated payment rows;
- turns; and
- payment periods.

This prevents the members, payment, and detail screens from showing different
snapshots of the same committee.

---

## Creating a committee

The create-committee workflow collects all required data before writing the
committee:

1. Enter a unique committee name.
2. Optionally enter a description.
3. Enter the contribution amount.
4. Choose a frequency:
   - daily;
   - weekly;
   - every two weeks;
   - monthly; or
   - quarterly.
5. Choose the first collection date.
6. Add the complete member roster.
7. Review the calculated pot and total collection.
8. Accept the terms dialog.
9. Submit the committee.

The service validates:

- name format and length;
- contribution minimum and maximum;
- start-date rules;
- member names and contact fields;
- minimum member count; and
- maximum supported member count.

At least two members are required. The same minimum is protected by the
database schema through the committee `member_count` check.

Creation is one transaction. The following are either all written or none are
written:

1. committee;
2. members;
3. periods;
4. turns; and
5. payment rows.

New committees start in the `active` state because the creation wizard already
requires the complete roster.

---

## Committee mathematics

Let:

- `C` = contribution amount;
- `N` = number of members; and
- `P` = number of periods.

The app uses:

```text
P = N
pot per turn = C x (N - 1)
payments per period = N - 1
total payment rows = N x (N - 1)
total money through the committee = N x C x (N - 1)
```

The collector is deliberately exempt from their own period. This is a
collector-exempt ROSCA variant:

```text
collector's own period: no payment row
all other members: one payment row for C
```

The common alternative ROSCA variant uses `C x N` and includes the collector's
own contribution. This app does not use that variant.

### Four-member example

For four members contributing Rs 10,000:

```text
pot per turn       = 10,000 x (4 - 1) = Rs 30,000
periods            = 4
payments per period= 3
total payment rows = 4 x 3 = 12
```

The period-one collector has no period-one payment row. The other three members
each have a Rs 10,000 row.

---

## Generated schedule

Schedules are generated from the start date and frequency. Dates are stored as
calendar dates without a time-of-day component.

| Frequency | Period `i` due date |
|---|---|
| Daily | `DateTime(y, m, d + i)` |
| Weekly | `DateTime(y, m, d + 7i)` |
| Every two weeks | `DateTime(y, m, d + 14i)` |
| Monthly | start date plus `i` calendar months, clamped to month end |
| Quarterly | start date plus `3i` calendar months, clamped to month end |

The first period is period 1 and is due on the selected start date.

For a monthly committee starting on January 31:

```text
January 31 -> February 28/29 -> March 31 -> April 30
```

The calculation is always based on the original start date. It does not
repeatedly add one month to the previous clamped date, so February 28 does not
cause later months to drift to the 28th.

Every period has:

- a period number;
- a label;
- a start date;
- a due date; and
- a closed/open state.

Every turn has:

- a turn number;
- a recipient member;
- a linked period;
- expected amount;
- collected amount;
- due date; and
- `upcoming`, `active`, or `completed` state.

---

## Managing members

Members are stored in turn order. The first member receives turn 1, the second
member receives turn 2, and so on.

Before any payment is marked paid, the organiser can:

- add a member;
- remove a member, subject to the minimum of two members;
- edit member details; and
- reorder collection turns.

Adding or removing a member rebuilds the generated periods, turns, and payment
matrix because the number of periods always equals the number of members.

Reordering changes which member receives each turn, so it also rebuilds the
derived schedule while payment history is empty.

Editing descriptive member information, such as a name or phone number, does
not rewrite financial history. Structural roster changes are different and are
blocked after the first payment is marked paid.

The roster lock is enforced twice:

1. in `CommitteeDetailProvider` for immediate UI feedback; and
2. in `MemberService` for protection against non-UI callers.

The existence of generated rows does not count as payment history. Rows are
pre-generated when a committee is created. Only rows whose status is `paid`
lock the roster.

---

## Recording payments

Payment rows are generated in advance. Marking a contribution paid updates an
existing pending row; it does not insert a second payment record.

When the organiser marks a row paid:

1. the service opens a database transaction;
2. the row is loaded inside that transaction;
3. an already-paid row is rejected with `DuplicateException`;
4. a conditional update changes `pending` to `paid`;
5. payment date, method, proof path, and notes are stored as applicable;
6. all turns are reconciled;
7. periods are closed or reopened as required;
8. committee status and completed-turn count are updated; and
9. the transaction commits.

If any step fails, the transaction rolls back. A payment cannot be persisted
without its corresponding turn and committee state.

### Payment methods

The payment form can record the selected method, including cash, supported
wallets, bank transfer, cheque, and other methods. Notes and optional proof
information can accompany the record.

### Duplicate taps

The same payment cannot be marked paid twice. The repository uses:

```sql
WHERE id = ? AND status = 'pending'
```

The affected-row count is checked. This protects against both repeated taps and
concurrent requests.

### Undoing a payment

An already-paid row can be marked pending again. This operation:

- clears its paid date;
- clears payment metadata that belongs to the paid transition;
- re-runs full turn reconciliation; and
- reopens the period if it is no longer complete.

Unmarking an already-pending row is rejected instead of silently succeeding.

---

## Turn and committee state workflow

Turn status is a pure function of period completion:

```text
completed = all expected payment rows in the period are paid
active    = earliest turn that is not completed
upcoming  = every other turn that is not completed
```

A period with zero payment rows is never considered completed. This prevents
the mathematical shortcut `0 >= 0` from completing an invalid one-member or
empty period.

Reconciliation recomputes all turns every time. It does not only patch the
turn touched by the latest payment.

### Normal order

```text
Turn 1 active
    |
all period-1 payments paid
    v
Turn 1 completed, period 1 closed
Turn 2 active
    |
all period-2 payments paid
    v
Turn 2 completed, period 2 closed
```

### Out-of-order completion

If period 3 is fully paid before period 2:

```text
Turn 3 completed
Turn 2 active
Turn 1 remains according to its own completion state
```

The completed-turn count is recalculated from the database rather than
incremented optimistically.

### Reopening and committee reversal

If a payment is unmarked:

1. its period becomes incomplete;
2. its turn becomes non-completed;
3. the period reopens;
4. the earliest incomplete turn becomes the only active turn;
5. later incomplete turns become upcoming;
6. `completedTurns` is recounted; and
7. a committee previously marked `completed` returns to `active`.

The committee is `completed` only when every turn is completed.

---

## Overdue workflow

Overdue is derived at runtime and is not stored in SQLite.

For an unpaid payment:

```text
overdue = today(date-only) is after dueDate(date-only)
```

Therefore:

- a payment due today at 00:00:01 is not overdue;
- a payment due today at 23:59:59 is not overdue;
- the same unpaid payment is overdue on the next calendar day; and
- a paid payment is never shown as overdue, even if it was paid late.

The severe-overdue calculation uses the same date-only rule and escalates after
the configured 30-day threshold.

The date calculation accepts an explicit `now` value in the domain model's
testable helpers. This makes due-date boundary behavior deterministic in tests.

Early collectors may receive their pot before they have made all later
contributions. That is an interest-free advance inherent in the ROSCA model.
The app does not change that behavior; it flags unpaid late obligations through
overdue status.

---

## Editing and data-protection rules

### Contribution amount

The contribution amount can be changed only while zero payment rows are marked
paid. When allowed, the service updates:

- the committee amount;
- all pending generated payment amounts; and
- all turn expected amounts.

Once any row is paid, changing the amount is rejected in both the service and
the provider.

### Roster rebuilds

`clearRows()` and every rebuild path refuse to run when paid rows exist. This
ensures that historical payment rows are never destroyed and silently
regenerated with a different member/order/amount meaning.

`ScheduleService.ensureFor()` can repair a missing or mismatched generated
schedule only when the committee has zero paid rows. If a mismatch is detected
alongside paid history, it surfaces a domain error and preserves the data.

### Deletion

Deleting a committee uses SQLite foreign-key cascades for its members,
periods, payments, and turns. Deletion is intentionally different from a
schedule rebuild: it is an explicit user operation on the whole committee.

---

## Dashboard and statistics

The dashboard derives its values from repository data and current dates. It can
show:

- active and completed committee counts;
- total collected and pending amounts;
- pending and overdue payment counts;
- current recipient;
- current turn progress;
- next due date; and
- committees that are behind their calendar schedule.

The collection screen prefers the oldest period that still has unpaid rows.
This is important for committees that started in the past but have not yet
collected their first period.

Statistics distinguish:

- money collected;
- money pending;
- expected pool;
- payment completion percentage;
- completed turns;
- remaining turns;
- current period; and
- calendar delay.

All monetary calculations use the collector-exempt formula described above.

---

## History and reports

History presents closed/completed periods and their recipient information.
Payment rows retain their paid date and recorded payment metadata.

The report service builds a committee report from:

- committee details;
- member roster;
- turn order;
- period schedule;
- payment status;
- collected and pending amounts; and
- completion information.

The generated PDF uses English labels and the shared filename:

```text
committee_report.pdf
```

Reports include the complete payment history. Large committees are paginated
in bounded payment-history table sections so a fully paid 14-member committee
with 182 generated payment rows can be exported without exceeding the PDF
layout engine's page-generation limit.

The report can be shared through the platform's share/printing integration.

---

## Notifications and reminders

The reminder service uses the generated schedule and turn information to plan
local notifications. Reminder content can cover:

- contributions approaching their due date;
- overdue contributions;
- upcoming collection turns; and
- committee activity.

Changing a roster before payment history exists or changing relevant settings
causes reminders to be rescheduled so notifications reflect the current
schedule.

Notifications are local application behavior. They do not change payment state.
Only an explicit payment action changes a row to `paid`.

---

## Settings and session security

Settings are stored locally through the settings repository. The settings area
supports the application's preferences, including:

- light/dark/system theme;
- supported language/locale choice;
- biometric unlock preference;
- lock/session behavior; and
- notification preferences where supported.

Authentication data is separated from business data. PIN hashes and salts are
stored through the secure local authentication flow. OTP challenge data is
stored separately and consumed after verification.

The application database export contains business entities but must not include
PIN hashes or OTP records.

---

## Persistence and migrations

The local database is managed by `AppDatabase` and `DbSchema`.

The main tables are:

| Table | Purpose |
|---|---|
| `users` | Local account and authentication metadata |
| `otp_challenges` | Hashed, expiring OTP challenges |
| `committees` | Committee configuration and lifecycle state |
| `members` | Committee roster and turn order |
| `schedules` | Generated periods and due dates |
| `payments` | One pre-generated obligation per member/period |
| `turns` | Recipient rotation and completion state |

Important database protections include:

- foreign keys with cascade behavior for dependent committee rows;
- unique committee names;
- unique member turn numbers per committee;
- unique payment identity per committee/member/period;
- positive period and turn numbers;
- non-negative amounts;
- valid payment and turn status values; and
- a minimum committee member count of two.

Schema changes are versioned. Existing installs are upgraded through migration
blocks rather than being silently recreated.

All repository operations use the database executor supplied by `AppDatabase`.
When a transaction is active, repository statements use the active transaction
executor, so composed service operations remain atomic.

---

## Application architecture

The project follows a layered architecture:

```text
Flutter screens/widgets
        |
ChangeNotifier providers
        |
Domain services
        |
Repository interfaces
        |
SQLite/shared-preference/HTTP implementations
        |
AppDatabase and schema
```

### Screens

Screens render state and forward user intent. They do not contain SQL or own
financial business rules.

### Providers

Providers load bundles, expose loading/error/data state, notify screens, and
provide immediate UI guards. They are not the final authorization boundary for
financial rules.

### Services

Services own validation, calculations, transaction boundaries, schedule
generation, payment transitions, reconciliation, reports, reminders, and
authentication workflows.

### Repositories

Repository interfaces define persistence contracts. SQLite implementations
translate those contracts into queries and map database failures into the
application exception hierarchy.

### Dependency injection

`ServiceLocator` is the composition root. It creates:

1. database infrastructure;
2. repositories;
3. calculators;
4. schedule and turn services;
5. payment and committee services;
6. providers and supporting services.

Tests can replace the database or registered dependencies without changing
screen code.

---

## Important source locations

### App entry and composition

- `lib/main.dart` - Flutter entry point.
- `lib/app.dart` - application widget and top-level configuration.
- `lib/di/service_locator.dart` - dependency graph.
- `lib/core/constants/app_routes.dart` - route constants.

### Authentication and session

- `lib/services/auth_service.dart`
- `lib/services/otp_service.dart`
- `lib/providers/auth_provider.dart`
- `lib/screens/auth/`
- `lib/widgets/auth_gate.dart`
- `lib/widgets/app_session_guard.dart`

### Committee workflow

- `lib/screens/committees/create_committee_screen.dart`
- `lib/screens/committees/committee_details_screen.dart`
- `lib/services/committee_service.dart`
- `lib/services/member_service.dart`
- `lib/services/schedule_service.dart`
- `lib/services/turn_service.dart`
- `lib/providers/committee_detail_provider.dart`

### Payments and calculations

- `lib/screens/payments/payments_screen.dart`
- `lib/services/payment_service.dart`
- `lib/services/payment_calculator.dart`
- `lib/models/payment.dart`
- `lib/models/committee_turn.dart`
- `lib/core/utils/app_date_utils.dart`

### Storage

- `lib/database/app_database.dart`
- `lib/database/db_schema.dart`
- `lib/repositories/interfaces/`
- `lib/repositories/implementations/`

### Reports and reminders

- `lib/services/report_service.dart`
- `lib/services/reminder_service.dart`
- `lib/services/statistics_service.dart`

---

## Local development

### Requirements

- Flutter SDK compatible with the version in `pubspec.yaml`;
- Dart SDK compatible with the declared environment;
- Android SDK for Android builds;
- Java/Gradle tooling supplied by the Flutter Android project; and
- an Android emulator or physical Android device for device testing.

### Install dependencies

From the repository root:

```powershell
flutter pub get
```

### Run the app locally

```powershell
flutter run
```

Core committee operations use the local SQLite database. If testing
registration or OTP, configure the selected OTP provider according to the
project's environment configuration.

### Useful commands

```powershell
flutter analyze
flutter test
flutter test --concurrency=1
flutter build apk --debug -PallowDebugSigning=true
```

The serial test command is useful when diagnosing tests that share platform
plugin state or produce large interleaved logs.

---

## Testing and verification

The test suite covers:

- application boot and dependency wiring;
- authentication and navigation;
- OTP delivery behavior;
- validators and money rules;
- date and due-date calculations;
- payment calculator formulas;
- committee creation and full lifecycle flows;
- database migrations;
- service edge cases; and
- integration/smoke workflows.

Business-logic verification should include the following scenarios:

1. Create a four-member committee with Rs 10,000.
2. Confirm 12 generated payment rows and three rows per period.
3. Confirm the collector has no row in their own period.
4. Complete period 3 before period 2 and verify period 2 is active.
5. Complete periods 1 and 2, then unmark period 1 and verify exactly one
   active turn and an active committee.
6. Mark a payment paid twice and verify rejection.
7. Attempt a roster or amount change after one paid row and verify rejection.
8. Attempt a schedule rebuild after one paid row and verify that no rows are
   deleted.
9. Test due-today and next-day overdue boundaries.
10. Test monthly scheduling from January 31 in leap and non-leap years.
11. Test a daily schedule across a month/year or DST boundary.
12. Verify transaction rollback by injecting a failure during reconciliation.
13. Reject a one-member committee.

Tests should assert both the returned error and the unchanged database state.

---

## Android builds and APK workflow

### Debug APK for local testing

The repository supports a debug-signed build without a release keystore:

```powershell
flutter build apk --debug -PallowDebugSigning=true
```

The output is normally:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

To place a copy on the Desktop:

```powershell
Copy-Item `
  build\app\outputs\flutter-apk\app-debug.apk `
  "$env:USERPROFILE\Desktop\committee_manager.apk" `
  -Force
```

This artifact is suitable for local installation and testing, not Play Store
release distribution.

### Release APK or App Bundle

Release builds require the private upload keystore and
`android/key.properties`. Those files must never be committed.

After configuring the signing files:

```powershell
flutter build apk --release
flutter build appbundle --release
```

If the app uses Supabase OTP, provide the required build-time definitions:

```powershell
flutter build appbundle --release `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

Before distributing a release:

1. install it on a real device;
2. register a test account;
3. receive and verify an OTP;
4. create a committee;
5. record and undo payments;
6. confirm lock and roster rules;
7. verify report sharing;
8. test notification behavior; and
9. confirm the release version and signing identity.

---

## Business assumptions

The app intentionally follows these assumptions:

1. A committee has at least two members.
2. The number of periods equals the number of members.
3. Each member receives exactly one turn.
4. The collector does not pay their own period.
5. A turn completes only when all other members' contributions for its period
   are marked paid.
6. A paid row is financial history and must not be destroyed by a repair.
7. Roster order and contribution amount cannot change after payment history
   exists.
8. A completed committee can return to active if a paid contribution is
   unmarked.
9. Overdue is a derived date-only status, not a stored flag.
10. An early collector receives an interest-free advance and remains responsible
    for later contributions.
11. Payout confirmation is separate from contribution collection; the current
    completion state means that contributions were collected, not that a
    separate handover event was confirmed.

For the detailed formula and rule reference, see
[`COMMITTEE_LOGIC.md`](./COMMITTEE_LOGIC.md). For the broader project and
architecture notes, see [`README.md`](./README.md).
