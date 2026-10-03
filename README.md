# Committee Manager

An offline-first Flutter application for running a **Bachat Committee** (also called a
committee, chit fund, ROSC, or "committee savings group") on a single Android phone.

A committee works like this: a fixed group of members pays a fixed contribution every
week or month. After every member has paid once, the entire pool is handed to one member
— the *collector*. Then the cycle repeats. The app exists to make sure that nobody loses
track of who has paid, whose turn it is, and how much has been collected.

Everything is stored in an on-device SQLite database. There is no server, no account
signup, and no network call in any core flow. The **only** network call is the one-time
email OTP that confirms the user owns the address they registered with, delivered via
Supabase Auth.

---

## 🚀 Play Store / Production Build — Required Steps

Before building a release APK or App Bundle for Google Play, you must wire in a
Supabase project. Without it the OTP verification screen cannot send or check codes,
and new users will be permanently stuck on registration.

### Step 1 — Create a free Supabase project

1. Go to [https://supabase.com](https://supabase.com) and sign up (free tier is enough).
2. Click **New project**, give it a name (e.g. "Committee Manager"), pick a region
   closest to your users, and click **Create new project**.
3. Wait ~2 minutes for provisioning to finish.
4. Go to **Project Settings → API**.
5. Copy two values:
   - **Project URL** — looks like `https://abcdefghijkl.supabase.co`
   - **Project API Keys → anon / public** — a long `eyJ…` string

### Step 2 — Enable Email OTP in Supabase

1. In your Supabase dashboard go to **Authentication → Providers → Email**.
2. Make sure **Enable Email provider** is on.
3. Set **OTP expiry** to `300` seconds (5 minutes, matching `AppConstants.otpValidity`).
4. Disable **Confirm email** (the app handles verification itself via the OTP screen).
5. Go to **Authentication → Email Templates → Magic Link** and customise the sender name
   if you like. The app uses `signInWithOtp` which sends this template.

### Step 3 — Build the release App Bundle

```powershell
flutter build appbundle --release `
  --dart-define=SUPABASE_URL=https://abcdefghijkl.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Replace the URL and key with your own values. The anon key is a **public** key — it is
safe to ship inside an APK. Row-level security on Supabase enforces what an anonymous
caller can do (request and verify an email OTP, nothing else).

### Step 4 — Verify before uploading

Run the app once on a real device with the release build:

```powershell
flutter run --release `
  --dart-define=SUPABASE_URL=https://abcdefghijkl.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Register a new account, confirm the OTP arrives in the inbox, enter it, and verify the
app reaches the dashboard. Then upload the `.aab` to the Play Console.

---
## Table of Contents

1. [Project Architecture](#project-architecture)
2. [Folder Structure](#folder-structure)
3. [pubspec.yaml](#pubspecyaml)
4. [Every File](#every-file)
5. [How to Run](#how-to-run)
6. [How the Application Works](#how-the-application-works)
7. [SOLID Explanation](#solid-explanation)
8. [Database Explanation](#database-explanation)
9. [Viva Questions and Answers](#viva-questions-and-answers)

---

## Project Architecture

### The one-way dependency rule

The project is a strict, five-layer stack. **Dependencies only ever point downwards.**

```
   ┌─────────────────────────────────────────────────────────────┐
   │  UI         Screens, Widgets                                 │
   │             Flutter widgets only. No SQL, no business rules.  │
   └────────────────────────────┬────────────────────────────────┘
                                │ watches / calls
   ┌────────────────────────────▼────────────────────────────────┐
   │  STATE      Providers (ChangeNotifier)                       │
   │             AsyncValue<T> + loading/error/data. No SQL.       │
   └────────────────────────────┬────────────────────────────────┘
                                │ calls
   ┌────────────────────────────▼────────────────────────────────┐
   │  DOMAIN     Services                                        │
   │             Business rules, validation, calculations,        │
   │             transactions. Knows nothing about Flutter.        │
   └──────────────┬─────────────────────────────┬────────────────┘
                  │ implements                  │ implements
   ┌──────────────▼─────────────┐   ┌───────────▼────────────────┐
   │  INTERFACES                │   │  IMPLEMENTATIONS           │
   │  repositories/interfaces   │   │  repositories/impl         │
   │  services/interfaces        │   │  services/impl             │
   │  (abstract contracts)       │   │  SQLite, SharedPrefs, HTTP  │
   └─────────────────────────────┘   └───────────┬────────────────┘
                                                  │
                                       ┌──────────▼──────────┐
                                       │  DATA               │
                                       │  AppDatabase,       │
                                       │  DbSchema           │
                                       └─────────────────────┘
```

Three rules make this stack worth anything:

1. **No SQL above the service layer.** Not in a screen, not in a provider. If a raw
   query appears in the UI, the architecture is already broken.
2. **Services depend on interfaces, never on implementations.** A service declares that
   it needs "some committee repository" and the composition root decides whether that is
   SQLite. This is what makes the services unit-testable with an in-memory database.
3. **Every asynchronous state is one of three things.** Not a bool `isLoading` next to a
   nullable list, which allows the impossible state "loading and empty because the request
   failed". `AsyncValue<T>` cannot represent that.

### The composition root

`lib/di/service_locator.dart` is the single place where the interface → implementation
choice is made. Nothing else in the project does `new` on a concrete repository. To swap
SQLite for a REST backend, you change one file.

### Data flow of a single user action

Taking "mark this payment as paid" as the concrete example:

```
User taps "Mark paid"
        │
        ▼
PaymentScreen.onPaid(payment)              UI      asks the provider
        │
        ▼
PaymentProvider.markPaid(payment)          STATE   sets AsyncValue.loading,
        │                                          calls the service, on error
        ▼                                          sets AsyncValue.failed
PaymentService.markPaid(...)               DOMAIN  opens a transaction, re-reads
        │                                          the period total, validates,
        ▼                                          writes, decides the next turn
PaymentRepository (interface)              CONTRACT
        │
        ▼
SqlitePaymentRepository                    IMPL    UPDATE payments …; the
        │                                          DatabaseExecutor is the active
AppDatabase                                DATA    Transaction, so it commits
```

Every arrow is an interface boundary. A test can replace any single arrow without
touching the others.

---

## Folder Structure

```
lib/
├── main.dart                          Entry point: binding, DI, runApp
├── app.dart                           Root widget, MultiProvider, MaterialApp, routes
│
├── core/                              Cross-cutting, no feature knowledge
│   ├── constants/
│   │   ├── app_constants.dart         App name, defaults, limits
│   │   └── app_routes.dart            Every named route in one place
│   ├── errors/
│   │   └── app_exception.dart         Domain exceptions + describeError()
│   ├── theme/
│   │   ├── app_theme.dart             Light and dark ThemeData
│   │   ├── app_colors.dart            Semantic colour tokens
│   │   └── app_spacing.dart           4pt spacing scale, radii, durations
│   └── utils/
│       ├── app_date_utils.dart        Month/week arithmetic, formatting
│       ├── crypto_helper.dart         SHA-256 PIN hashing, OTP hashing
│       ├── currency_formatter.dart    Symbol + grouping
│       ├── logger.dart                Namespaced AppLogger
│       └── validators.dart            Reusable form validators
│
├── database/                          The only code allowed to speak SQL
│   ├── app_database.dart              Open, migrate, transaction, guard
│   └── db_schema.dart                 CREATE TABLE / INDEX statements
│
├── models/                            Pure data. No Flutter, no SQL.
│   ├── enums.dart                     Frequencies, statuses, methods, roles
│   ├── committee.dart                 Committee aggregate
│   ├── member.dart                    Member + frozen copy
│   ├── payment.dart                   Payment with derived isOverdue
│   ├── payment_schedule.dart          Period definitions
│   ├── committee_turn.dart            One member's turn
│   ├── statistics.dart                DashboardStats, PeriodCollection
│   ├── app_user.dart                  Single local user
│   ├── app_settings.dart              Persisted preferences
│   ├── otp_challenge.dart             Pending OTP
│   └── notification_payload.dart      Reminder payloads
│
├── repositories/
│   ├── interfaces/                    Abstract contracts (7)
│   │   ├── committee_repository.dart
│   │   ├── member_repository.dart
│   │   ├── payment_repository.dart
│   │   ├── schedule_repository.dart
│   │   ├── turn_repository.dart
│   │   ├── user_repository.dart
│   │   └── settings_repository.dart
│   └── implementations/               SQLite + SharedPreferences (7)
│       ├── sqlite_committee_repository.dart
│       ├── sqlite_member_repository.dart
│       ├── sqlite_payment_repository.dart
│       ├── sqlite_schedule_repository.dart
│       ├── sqlite_turn_repository.dart
│       ├── sqlite_user_repository.dart
│       └── shared_preferences_settings_repository.dart
│
├── services/                          Business logic
│   ├── interfaces/                    Abstract contracts (3)
│   │   ├── biometric_service.dart
│   │   ├── notification_service.dart
│   │   └── otp_sender.dart
│   ├── implementations/               Platform-backed (4)
│   │   ├── local_biometric_service.dart
│   │   ├── local_notification_service.dart
│   │   ├── in_app_otp_sender.dart     Default: shows the code in-app
   |   +-- http_otp_sender.dart       Sends a real code through the email gateway
│   ├── auth_service.dart              Registration, login, PIN, lock
│   ├── otp_service.dart               Issue, verify, expire, resend
│   ├── committee_service.dart         Committee CRUD + status lifecycle
│   ├── member_service.dart            Roster rules (no removal after payout)
│   ├── schedule_service.dart          Generates the full payment schedule
│   ├── payment_service.dart           Recording, validation, pot handover
│   ├── turn_service.dart              Whose turn, and advancing it
│   ├── payment_calculator.dart        Pure money maths
│   ├── statistics_service.dart        Aggregations and trends
│   ├── reminder_service.dart          Schedules/cancels due-date reminders
│   └── demo_data_service.dart         Safe sample data, and full wipe
│
├── providers/                         ChangeNotifier state holders
│   ├── auth_provider.dart
│   ├── committee_provider.dart        Also defines AsyncValue<T>
│   ├── committee_detail_provider.dart
│   ├── dashboard_provider.dart
│   ├── history_provider.dart
│   ├── statistics_provider.dart
│   ├── payment_provider.dart
│   ├── settings_provider.dart
│   └── theme_provider.dart
│
├── widgets/                           Shared, stateless UI
│   ├── app_card.dart                  AppCard, StatTile, StatusChip, AppProgressBar
│   ├── state_views.dart               Loading / Empty / Error / SplashBody
│   ├── entity_tiles.dart              CommitteeTile, MemberTile
│   ├── auth_gate.dart                 Maps AuthStage → the right screen
│   └── edit_sheets.dart               Reusable form sheets
│
└── screens/                           Feature UI
    ├── splash/splash_screen.dart
    ├── auth/register_screen.dart
    ├── auth/verify_otp_screen.dart
    ├── auth/lock_screen.dart
    ├── shell/app_shell.dart           Bottom navigation
    ├── dashboard/dashboard_screen.dart
    ├── committees/committees_screen.dart
    ├── committees/create_committee_screen.dart
    ├── committees/committee_details_screen.dart
    ├── members/members_screen.dart
    ├── payments/payments_screen.dart
    ├── history/history_screen.dart
    ├── statistics/statistics_screen.dart
    └── settings/settings_screen.dart
```

---

## pubspec.yaml

```yaml
name: committee_manager
description: "Committee Manager - offline-first Bachat Committee / Committee management app."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.13.4

dependencies:
  flutter:
    sdk: flutter

  provider: ^6.1.2                     # State management
  sqflite: ^2.4.1                      # On-device relational database
  path: ^1.9.0                         # Locates the database file
  flutter_local_notifications: ^19.0.0 # Due-date reminders
  timezone: ^0.10.0                    # Timezone-aware scheduling
  flutter_timezone: ^4.0.0             # Reads the device timezone
  intl: ^0.20.2                        # Date and number formatting
  uuid: ^4.5.1                         # Collision-free record ids
  crypto: ^3.0.6                       # SHA-256 for PINs and OTPs
  local_auth: ^2.3.0                   # Biometric unlock
  local_auth_android: ^1.0.46          # Android BiometricPrompt
  shared_preferences: ^2.3.3           # Settings storage
  http: ^1.2.2                         # Optional real OTP gateway

dev_dependencies:
  flutter_test:
    sdk: flutter
  sqflite_common_ffi: ^2.3.4           # Runs sqflite on the Dart VM for tests
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

### Why each dependency earns its place

| Package | Why it is here | Why not something else |
| --- | --- | --- |
| `provider` | Small, debuggable, no codegen | `bloc` would add ceremony for eight state classes |
| `sqflite` | Real SQL, real transactions, real constraints | Drift adds generated code for a schema this size |
| `flutter_local_notifications` | Scheduled, timezone-correct reminders | FCM would need a server and a network |
| `crypto` | SHA-256 is in the Dart SDK; no native crypto needed | `encrypt` would need key management we do not need |
| `local_auth` | System biometric prompt | Re-implementing a fingerprint UI is madness |
| `shared_preferences` | Right tool for a handful of scalars | A SQLite table would be overkill for theme + currency |
| `http` | Only used by the opt-in OTP sender | Avoids pulling in a heavy API client for 30 lines |
| `sqflite_common_ffi` | **Test-only.** Lets `sqflite` run on the desktop VM | Without it the business rules could not be tested at all |

Note: `INTERNET` is intentionally **not** declared in `AndroidManifest.xml`. The app is
fully functional with no network. Real OTP delivery is opt-in from Settings; see
[How the Application Works](#how-the-application-works).

---

## Every File

### Entry point

#### `lib/main.dart`
Does exactly three things, and nothing else: binds the framework, installs a
`FlutterError.onError` logger, and builds the object graph before the first frame. Locking
the app to portrait happens here too. If the database cannot be opened it renders
`_StartupFailureApp` rather than crashing into a red screen.

### Root

#### `lib/app.dart`
`CommitteeManagerApp` (a `StatelessWidget`) builds a `MultiProvider` containing every
provider in the app, then a `MaterialApp` configured from `ThemeProvider`, and an
`onGenerateRoute` that maps `AppRoutes` to screens. Because the router is a function, the
app has no named-route registration to keep in sync and deep links are impossible to get
wrong.

### `core/`

#### `lib/core/constants/app_constants.dart`
Application name, default contribution, committee limits, and storage keys. Anything a
user could reasonably want to change about the app's defaults belongs here.

#### `lib/core/constants/app_routes.dart`
Every route name as a `const String`. Used in `pushNamed` calls, so a typo is a compile
error rather than a runtime black hole.

#### `lib/core/errors/app_exception.dart`
The domain's exception vocabulary: `ValidationException`, `DuplicateException`,
`NotFoundException`, `AuthException`, `OtpException`, `DatabaseException`. Plus
`describeError(Object)` which turns any thrown object into a sentence safe to show a
user — the UI never shows a raw stack trace.

#### `lib/core/theme/app_theme.dart`
Builds `ThemeData` for light and dark from one seed colour. Centralised so that a change
to the brand colour does not require hunting through twenty screens.

#### `lib/core/theme/app_colors.dart`
Semantic tokens — `success`, `warning`, `danger`, `info`, `brandIndigo`, `brandTeal` —
plus the dark-mode-aware surface pair. Re-exports `app_spacing.dart`.

#### `lib/core/theme/app_spacing.dart`
A 4pt spacing scale — `xxs` = 2, `xs` = 4, `sm` = 8, `md` = 12, `lg` = 16, `xl` = 20,
`xxl` = 24, `xxxl` = 32, plus `page` = 16 for standard horizontal padding. `AppRadius`
supplies the corner radii (`sm` 8 → `xl` 24, and `pill` 999). No screen hard-codes `16.0`.

#### `lib/core/utils/app_date_utils.dart`
Month-end-safe arithmetic (`addMonths(31 Jan) = 28/29 Feb`, not 3 March), `dateOnly`,
and all date formatting. Committee due dates are wrong in a surprising number of apps
because nobody wrote this class; here it exists and is tested.

#### `lib/core/utils/crypto_helper.dart`
`hashSecret(secret, salt, {rounds = 25000})` — 25,000 rounds of SHA-256, which is key
stretching, for PIN and OTP hashes. `secureEquals(a, b)` is a constant-time comparison so
verification cannot be timed. Also `newId()` (UUID v4), `numericOtp()`, `newSalt()` and
`randomSecret()` (from `Random.secure()`). A PIN is never stored or logged in plain text.

#### `lib/core/utils/currency_formatter.dart`
Formats a `double` with a currency symbol and thousands separators, and converts between
currencies when the user changes the setting in Settings.

#### `lib/core/utils/logger.dart`
A namespaced wrapper over `debugPrint` that keeps output tidy. Namespaces mean
`AppLogger('PaymentService')` is greppable.

#### `lib/core/utils/validators.dart`
Reusable `FormFieldValidator`s: required, min length, digits only, amount range, phone
format, strong PIN. Screens compose these instead of re-writing regex.

### `database/`

#### `lib/database/app_database.dart`
Owns the `sqflite` database. It opens lazily behind a `Completer` so two concurrent
callers cannot open two connections, runs the schema, exposes `executor`, re-enters an
existing `Transaction` instead of deadlocking, and offers `guardAsync` (wrap an operation
and convert a raw `DatabaseException` into a readable message), `wipe()` for "erase
everything", and `close()` for tests.

The important subtlety is `executor`:

```dart
Database? _db;
Transaction? _activeTransaction;

Future<DatabaseExecutor> get executor async => _activeTransaction ?? await database;
```

Services pass a `DatabaseExecutor` down to repositories. Inside a transaction, every
statement therefore runs *on that transaction* and shares its commit. Without this, the
first `await repository.getX()` inside a transaction would try to use a different
connection while the transaction held the write lock — a real deadlock, which is exactly
what the test suite caught.

#### `lib/database/db_schema.dart`
All DDL in one place, as `const String` fields: `createUsers`, `createOtpChallenges`,
`createCommittees`, `createMembers`, `createSchedules`, `createPayments`, `createTurns`,
plus the six index statements, assembled in `createStatements` in dependency order — a
table must exist before its index, and before another table's `FOREIGN KEY` can point at
it. Every foreign key has `ON DELETE CASCADE`, so deleting a committee removes its
members, periods, payments and turns in one statement.

### `models/`

#### `lib/models/enums.dart`
`PaymentFrequency` (weekly / biweekly / monthly / quarterly), `CommitteeStatus`,
`TurnStatus`, `PaymentStatus`, `PaymentFilter`, `PaymentMethod`, `MemberRole`, `OtpChannel`,
`UserRole`, `AppThemePreference`. Each carries its own `label`, `description`, `icon`, and
`fromStorage` with a safe `orElse`, so a database value that no longer exists in a later
build degrades gracefully instead of crashing.

`PaymentFrequency` also owns the *date maths* (`nextDueDate`, `dueDateForPeriod`,
`periodLabel`). Putting that here rather than in a service is what makes a new frequency
a one-line change.

#### `lib/models/committee.dart`
`Committee`: id, unique name, contribution amount, start date, frequency, duration in
periods, member count, current and completed turn counters, and status. The derived
getters are where the money lives:

- `totalPoolPerTurn` → `contributionAmount * memberCount` (the pot for one period)
- `expectedTotalCollection` → `contributionAmount * durationPeriods`
- `firstDueDate` / `lastDueDate` → delegate to `PaymentFrequency.dueDateForPeriod`
- `remainingTurns`, `progressPercent`, `isActive`, `isCompleted`, `isEditable`

#### `lib/models/member.dart`
`Member`: identity, contact, `turnNumber` (their slot in the rotation), role, and
`isActive`. `initials` derives the avatar text from the name, `isOrganizer` wraps the role
check. There is deliberately **no** per-member contribution override — a committee has one
contribution amount, enforced by the `committees.contribution_amount` column, so allowing
per-member amounts would make the pot formula ambiguous.

#### `lib/models/payment.dart`
`Payment`: period, member, amount, due date, status, method, notes, and the paid
timestamp. `isOverdue`, `isDueToday`, `daysOverdue` and `effectiveStatus` are all
**getters** — overdue-ness depends on today's date, so storing it would mean it goes
stale the moment the app is not opened.

#### `lib/models/payment_schedule.dart`
`PaymentSchedule`: one period — number, human-readable `label`, start/due date, and
`isClosed`.

#### `lib/models/committee_turn.dart`
`CommitteeTurn`: which member collects (`memberId`), in which order (`turnNumber`),
the `expectedAmount` pot, how much has been `collectedAmount`, and `TurnStatus`.

#### `lib/models/statistics.dart`
`DashboardStats` and `PeriodCollection` — plain aggregates returned by
`StatisticsService`, with no knowledge of where the numbers came from.

#### `lib/models/app_user.dart`
`AppUser`: the single local account — name, phone, email, hashed PIN.

#### `lib/models/app_settings.dart`
`AppSettings`: theme, currency, reminder toggles, biometric flag, OTP channel, and the
optional gateway URL. Immutable; `copyWith` produces updates.

#### `lib/models/otp_challenge.dart`
`OtpChallenge`: hashed code, channel, destination, attempts, expiry, and `isExpired`.

#### `lib/models/notification_payload.dart`
A plain data object passed to the notification service, so the service takes intent
rather than importing UI concerns.

### `repositories/interfaces/`

#### `lib/repositories/interfaces/committee_repository.dart`
Declares create, find-by-id, list, update, delete, change-status, and name-exists.
#### `.../member_repository.dart`
Declares roster reads/writes, ordering, and bulk insert. No business rules — it does not
know a committee has a maximum size.
#### `.../payment_repository.dart`
Declares payment queries, aggregation, and the sum for one period.
#### `.../schedule_repository.dart`
Declares period generation, reads, and the next unpaid period.
#### `.../turn_repository.dart`
Declares turn reads, current turn, advance, and completion counts.
#### `.../user_repository.dart`
Declares the single-user get/upsert/delete.
#### `.../settings_repository.dart`
Declares load/save/clear. Note the parameter is `Object`, satisfied by
`SharedPreferences` in production and a plain `Map` in tests.

### `repositories/implementations/`

#### `lib/repositories/implementations/sqlite_committee_repository.dart`
Maps `committees` rows to `Committee`. `create` catches the `UNIQUE` constraint violation
and rethrows `DuplicateException('A committee with this name already exists')`, so the
user sees a sentence rather than "database error 2067".

#### `lib/repositories/implementations/sqlite_member_repository.dart`
CRUD plus `reorder`, which writes a single transaction that rewrites every `sort_order`.
#### `lib/repositories/implementations/sqlite_payment_repository.dart`
Payment writes and the aggregations the dashboard needs (`collectionByPeriodAll`,
totals, counts).
#### `lib/repositories/implementations/sqlite_schedule_repository.dart`
Bulk period generation and period lookups.
#### `lib/repositories/implementations/sqlite_turn_repository.dart`
Turn lookup and advancement. `advance` is a `CASE` expression, so it is one atomic
statement rather than read-then-write.
#### `lib/repositories/implementations/sqlite_user_repository.dart`
Single-row user storage.
#### `lib/repositories/implementations/shared_preferences_settings_repository.dart`
Serialises `AppSettings` to a JSON string under one key. One key means one read, one
write, and no partial states.

### `services/interfaces/` and `services/implementations/`

#### `lib/services/interfaces/biometric_service.dart`
`isAvailable()`, `authenticate(reason)`.
#### `lib/services/interfaces/notification_service.dart`
`initialize()`, `show(payload)`, `schedule(payload)`, `cancel(id)`, `requestPermission()`.
#### `lib/services/interfaces/otp_sender.dart`
`send(challenge)`. The seam that lets the app be offline *and* eventually real.

#### `lib/services/implementations/local_biometric_service.dart`
Wraps `local_auth`, translating its `PlatformException`s into `AuthException` with a
readable message.
#### `lib/services/implementations/local_notification_service.dart`
Initialises channels, requests `POST_NOTIFICATIONS` on Android 13+, and schedules with
`zonedSchedule` using the device timezone.
#### `lib/services/implementations/in_app_otp_sender.dart`
The **default**. Does not send anything: it returns the code so `VerifyOtpScreen` can
display it in a "demo code" banner. This is what makes the app testable with no network.
#### `lib/services/implementations/http_otp_sender.dart`
`POST`s `{ phone, email, code, message }` to the gateway URL from Settings. Only
constructed when a gateway is configured, and the `INTERNET` permission is opt-in.

### `services/`

#### `lib/services/auth_service.dart`
Registration (validate → hash PIN → create user → issue OTP), login, PIN verification,
`enableLock`/`disableLock`, and biometric unlock. The PIN is compared with a
constant-time equality check.
#### `lib/services/otp_service.dart`
Issue (generate 6 digits, hash, store with a 5-minute expiry), verify (constant-time
compare, decrement attempts, expire), and resend with a 30-second cooldown. Returns
generic "incorrect or expired" text so it cannot be used to probe valid codes.
#### `lib/services/committee_service.dart`
Committee creation — validates uniqueness, then opens **one transaction** that inserts the
committee, its members, its schedule, and its turns together. Either the committee exists
completely or not at all. Also owns the status lifecycle (`draft → active → completed →
archived`) and deletion.
#### `lib/services/member_service.dart`
Roster rules: a member may not be removed once they have received the pot, because
history would become unexplainable. Contribution overrides must be positive.
#### `lib/services/schedule_service.dart`
Generates the whole schedule: `duration == memberCount` periods, each with the due date
from `PaymentFrequency.dueDateForPeriod` and a pot of `memberCount × contribution`. Called
inside the committee-creation transaction.
#### `lib/services/payment_service.dart`
Recording a payment: rejects a payment for a completed period, rejects a duplicate,
recalculates the period total, marks the period collected when the pot is reached, and
advances the turn. This is the most rule-dense class in the project, and it is entirely
free of Flutter imports.
#### `lib/services/turn_service.dart`
Answers "whose turn is it?" and performs the handover atomically.
#### `lib/services/payment_calculator.dart`
Pure functions: pot size, expected totals, paid ratios, currency conversion. No I/O, so
it is trivially testable and obviously correct by inspection.
#### `lib/services/statistics_service.dart`
`dashboard()` and `allHistory()` in one pass, plus `collectionTrend()` for the chart.
#### `lib/services/reminder_service.dart`
Schedules a notification one day before each due date and cancels it once the period is
settled. Reschedules everything on app start so alarms survive a reboot.
#### `lib/services/demo_data_service.dart`
Inserts a realistic sample committee, and `eraseAll()` for a clean slate. Both run in one
transaction so a failure cannot leave a half-loaded database.

### `providers/`

#### `lib/providers/committee_provider.dart`
The committee list, and the home of the shared `AsyncValue<T>` used by every provider:

```dart
enum LoadState { idle, loading, ready, failed }

class AsyncValue<T> {
  const AsyncValue({this.state = LoadState.idle, this.data, this.error});

  const AsyncValue.idle()     : this(state: LoadState.idle);
  const AsyncValue.loading({T? previous}) : this(state: LoadState.loading, data: previous);
  const AsyncValue.ready(T value)  : this(state: LoadState.ready, data: value);
  const AsyncValue.failed(String message) : this(state: LoadState.failed, error: message);

  final LoadState state;
  final T? data;
  final String? error;

  bool get isLoading => state == LoadState.loading;
  bool get isReady   => state == LoadState.ready;
  bool get hasError  => state == LoadState.failed;
  bool get isEmpty   => data == null;
}
```

`loading` carries the previous `data`, so a refresh keeps the old list on screen instead
of flashing a spinner — the difference between "reloading" and "have never loaded". Having
one union type is what removes the `bool isLoading` + `T? items` + `String? error` triple
that usually drifts out of sync.

#### `lib/providers/auth_provider.dart`
The `AuthStage` state machine (`loading → unauthenticated → verifying → authenticated →
locked`) plus registration, login, logout, and biometric unlock.
#### `lib/providers/committee_detail_provider.dart`
One committee with its members, schedule, and turns, and a `refresh()` that the child
screens call so a recorded payment immediately updates the header.
#### `lib/providers/dashboard_provider.dart`
Headline statistics plus reminders, refreshed on pull-to-refresh.
#### `lib/providers/history_provider.dart`
Every period across every committee, newest first, with a committee filter chip and
`grouped` for rendering as sections. Its own read model, because history needs different
aggregates than the dashboard.
#### `lib/providers/statistics_provider.dart`
Totals, turn progress, and the `collectionTrend()` series for the chart.
#### `lib/providers/payment_provider.dart`
The payments of one period, plus search, status filter, and the mark-paid / mark-unpaid
actions. Switching period resets the filters, because a filter that silently refers to a
different list is a bug.
#### `lib/providers/settings_provider.dart`
Every setting, and the destructive actions (`seedDemoData`, `eraseAllData`) each behind
its own confirmation.
#### `lib/providers/theme_provider.dart`
`AppThemePreference` → `ThemeMode`, persisted immediately.

### `widgets/`

#### `lib/widgets/app_card.dart`
`AppCard`, `AppIconBadge`, `StatTile`, `AppProgressBar`, `StatusChip`, `SectionLabel`. The
visual vocabulary of the app, so a card looks the same on every screen.
#### `lib/widgets/state_views.dart`
`LoadingState`, `EmptyState`, `ErrorState` (with retry), `SplashBody`. Every list in the
app handles all four, which is why no screen shows an infinite spinner on an error.
#### `lib/widgets/entity_tiles.dart`
`CommitteeTile` and `MemberTile` — list rows with avatar initials, status dot, and
progress. Extracted so the dashboard and the committee list cannot drift apart.
#### `lib/widgets/auth_gate.dart`
Maps `AuthStage` to the correct screen, so the root widget is one line instead of a
nested-if ladder.
#### `lib/widgets/edit_sheets.dart`
`showEditCommitteeSheet` and `showEditMemberSheet` — modal bottom sheets with forms and
validation, reused by the details screen and the create screen.

### `screens/`

#### `lib/screens/splash/splash_screen.dart`
A branded splash that awaits `AuthProvider.bootstrap()` then routes to the shell.
#### `lib/screens/auth/register_screen.dart`
Name, phone, email, PIN, confirm PIN, with live validation and inline errors.
#### `lib/screens/auth/verify_otp_screen.dart`
Six-box OTP entry, resend with cooldown, and the demo-code banner when the in-app sender
is active.
#### `lib/screens/auth/lock_screen.dart`
PIN pad and a biometric button. The only screen reachable without unlocking.
#### `lib/screens/shell/app_shell.dart`
`NavigationBar` with Dashboard, Committees, History, and Settings, preserving each tab's
navigation stack via `IndexedStack`.
#### `lib/screens/dashboard/dashboard_screen.dart`
Greeting, the current turn with its collector, collected-vs-expected progress, quick stats,
upcoming reminders, and recent committees.
#### `lib/screens/committees/committees_screen.dart`
Search, status filter, `CommitteeTile` list, and FAB to create.
#### `lib/screens/committees/create_committee_screen.dart`
Name, contribution, frequency, start date, and the member list with live add/remove. Shows
the pot and the expected total **as you type** — the user should never discover the
arithmetic on the confirmation screen.
#### `lib/screens/committees/committee_details_screen.dart`
Header with progress, then Overview / Members / Periods tabs. Edit, archive, and delete
(with confirmation) live here.
#### `lib/screens/members/members_screen.dart`
Roster with add, edit, remove, per-member progress, and a reorder sheet that defines the
collection order.
#### `lib/screens/payments/payments_screen.dart`
Period selector, search, filter chips, per-member payment rows, tap to mark paid/unpaid
with a method picker, "mark all paid", and pull-to-refresh.
#### `lib/screens/history/history_screen.dart`
Read-only log of settled periods with a committee filter and per-committee sections.
Deliberately not editable — it is a record of what happened.
#### `lib/screens/statistics/statistics_screen.dart`
Turn-progress card, four stat tiles, and a bar chart of collection per period. The chart
is a ~60-line `CustomPainter`: for a single bar series, that is smaller than any charting
dependency and it follows the app's own colours.
#### `lib/screens/settings/settings_screen.dart`
Profile, theme, currency, reminders, security (biometrics, change PIN), OTP gateway,
demo data, erase all, and an about section with the version.

### Tests

#### `test/committee_flow_test.dart`
17 tests over the real SQLite database (via `sqflite_common_ffi`, in-memory) covering
committee creation, schedule generation, the pot formula, payment recording, turn
advancement, handover, history, statistics, and the uniqueness constraint.

#### `test/validators_test.dart`
22 tests over the form validators — PIN, OTP, phone, email, member name.

Every one of these asserts that a **valid** input returns `null`, because that is the
direction that is easiest to get wrong and the most damaging. An inverted predicate
rejects everything, reads fine in review, and makes the feature unusable. `Validators.pin`
*was* inverted: `_digitsOnly` is `[^0-9]`, so a match means a bad character is present,
but the check read `if (!_digitsOnly.hasMatch(raw))`. Every PIN in the app was rejected
with "PIN must contain digits only" — **registration was impossible on a real device, and
no other test noticed**, because the service tests never went through the validators and
the analyzer has nothing to say about it. `Validators.otp` had the same inverted check.

#### `test/app_boot_test.dart`
7 tests that mount the real widget tree.

`flutter analyze` and the service tests both stay green while the app is completely
broken: a mistyped provider constructor, a service the composition root never registered,
or a `context.watch` of something absent. None of those are compile errors, and all of
them crash on the first frame. This file wires the real `ServiceLocator` against a real
in-memory database and pumps `CommitteeManagerApp` exactly as `main()` does, then asserts
`AuthGate` maps each `AuthStage` to the right screen.

It overrides the `stage` getter rather than calling the real `bootstrap()`, because
`bootstrap()` awaits `local_auth`, which uses a Pigeon channel that no unit test can
answer — the future never completes and the test hangs. That is a useful thing to know
about the app as well as the test.

### Android

#### `android/app/src/main/AndroidManifest.xml`
Declares only the permissions the app actually uses: `POST_NOTIFICATIONS`,
`RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `VIBRATE`,
`USE_BIOMETRIC`. `INTERNET` is present but commented out, with a note explaining that
real OTP is opt-in. Includes the `ScheduledNotificationReceiver` and
`ScheduledNotificationBootReceiver` so reminders survive a reboot.
#### `android/app/src/main/kotlin/.../MainActivity.kt`
Extends `FlutterFragmentActivity`, not `FlutterActivity`. The biometric prompt is a
fragment, so `local_auth` cannot attach it to a plain activity — this is the single most
common cause of "biometrics never appear" on Android.
#### `android/app/build.gradle.kts`
Java 17, `minSdk = 23` (local_auth's floor), core library desugaring (so
`flutter_local_notifications` can use `java.time` on older APIs), `multiDexEnabled`, and
R8 minification with `proguard-rules.pro` keeping the reflection-reached plugin classes.

---

## How to Run

### Requirements

| Tool | Version used |
| --- | --- |
| Flutter | 3.47.5 |
| Dart | 3.13.4 |
| Android SDK | 36.0.0 |
| JDK | 17 (OpenJDK 17.0.20.1) |

### First-time setup

```bash
flutter pub get
flutter doctor -v          # confirm the Android toolchain is green
```

### Run on a device or emulator

```bash
flutter devices            # list targets
flutter run                # debug, with hot reload
```

### Build the release APK

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

> **Note on signing.** The release build is signed with the debug keys so that
> `flutter build apk --release` works immediately. Replace the `signingConfig` in
> `android/app/build.gradle.kts` with a real key before publishing to Play.

### Run the tests

```bash
flutter test
```

Expected:

```
00:07 +46: All tests passed!
```

### Static analysis and formatting

```bash
flutter analyze            # must report "No issues found!"
dart format lib test --line-length 100
```

### First launch

1. The app opens on the **splash** screen, builds the database, and shows **Register**.
2. Enter a name, phone, and a 4–6 digit PIN.
3. Tap **Send code**. With the default in-app sender, the 6-digit code appears in a banner
   on the verification screen.
4. Enter the code → you land on the **Dashboard**.
5. Tap **Create committee** to try the full flow.

---

## How the Application Works

### The domain, in one paragraph

A **committee** has a name, a contribution amount, a start date, a **frequency** (weekly,
biweekly, monthly, or quarterly), and a group of **members**. The number of periods equals
the number of members. Period *n* is due on the date the frequency produces from the
start date, and each period's **pot** is `memberCount × contribution`. Every member must
pay once in a period; when all have paid, the pot is handed to that period's
**collector**, who is the member whose **turn** it is. Then the period is settled, the turn
advances, and history records it.

Worked example — three members, Rs. 1,000 each, monthly, starting 1 Jan 2026:

| Period | Due | Pot | Who collects |
| --- | --- | --- | --- |
| 1 | 1 Feb 2026 | Rs. 3,000 | Member A |
| 2 | 1 Mar 2026 | Rs. 3,000 | Member B |
| 3 | 1 Apr 2026 | Rs. 3,000 | Member C |

Expected total across the committee: `3 × 3,000 = Rs. 9,000`.

### Why the duration equals the member count

This is the defining rule of a Bachat committee, and it is why `Committee.duration` is
never a free-text field in the UI: it is derived. Making it editable would let a user
create a committee that quietly contradicts its own schedule.

### The status lifecycle

```
draft ──▶ active ──▶ completed ──▶ archived
  │           │                        │
  └── edit ───┘                        └──▶ (hidden from dashboard)
```

- **draft** — created but not started; editable, nothing is due.
- **active** — collecting. Reminders fire, the dashboard tracks it.
- **completed** — every member has received the pot.
- **archived** — finished and hidden, but never deleted, so history survives.

### Screens and what each one does

| Screen | Purpose |
| --- | --- |
| Splash | Builds the database, resolves the auth state, routes onward |
| Register | Creates the single local account and issues an OTP |
| Verify OTP | Confirms the code; shows the demo code for the in-app sender |
| Lock | PIN or biometric unlock — the only screen reachable while locked |
| Dashboard | Current turn, progress, reminders, recent committees |
| Committees | Search and filter every committee; create a new one |
| Create committee | Live pot/total preview while building the roster |
| Committee details | Overview, members, periods; edit, archive, delete |
| Members | Roster, per-member progress, reorder = collection order |
| Payments | Record and review the payments of one period |
| History | Read-only log of settled periods |
| Statistics | Totals, turn progress, collection trend |
| Settings | Theme, currency, reminders, security, OTP gateway, data |

### One-time codes: the gateway

There is **no in-app code display**. The app has exactly one way to deliver a
one-time code: an HTTP gateway that really sends it **by email**. The code
itself never comes back into the app process, so possession of the phone is not
enough to register — the user also has to prove they control the address they
typed.

Email is the only channel, deliberately. SMS would mean a paid provider,
per-country sender-ID rules, and a second failure mode to explain in the UI,
none of which the app needs in order to collect a committee. An account's
phone number is kept only as a contact detail and is never used to deliver
anything.

`ServiceLocator` always registers `HttpOtpSender`, which `POST`s to
`AppConfig.otpGatewayUrl`:

```json
{
  "channel": "email",
  "destination": "user@example.com",
  "code": "483920",
  "purpose": "Account verification"
}
```

The gateway that receives it lives in [`otp_gateway_server/`](otp_gateway_server/)
and delivers over SMTP. See its [README](otp_gateway_server/README.md) for the
full setup.

#### Where the code is sent

`AppUser.primaryChannel` is always `OtpChannel.email`, and
`verificationTarget` is the account's email address. A phone number on file is
never a delivery target, so there is no channel for a send to fail on and
nothing for a locked-out user to choose between.

Accounts created before SMS was removed may still have `'sms'` stored in
`preferred_otp_channel`; `OtpChannel.fromStorage` maps that to `email` so those
rows keep loading.

#### Configuring the endpoint

| Where the app runs | Endpoint to use |
| --- | --- |
| Android emulator | `http://10.0.2.2:4000/otp` (the default) |
| Physical phone, same Wi-Fi | `http://<your-computer-LAN-IP>:4000/otp`, set in **Settings → OTP Gateway** |
| Any host | Override at build time with `--dart-define=OTP_GATEWAY_URL=...` |

Add `--dart-define=OTP_API_KEY=...` if the gateway is started with
`OTP_API_KEY` set. The key is sent as the `x-otp-key` header and is only required
on `POST /otp` — `GET /health` stays open so it can be polled.

Plain HTTP is permitted only for the loopback and private addresses the app
actually needs (`10.0.2.2`, `localhost`, the local network range), via
`network_security_config.xml`. Everything else still requires HTTPS.

### Security posture

- The PIN is **never** stored. Only `sha256(pin + salt)`, stretched, is.
- The PIN *length* is stored, so the lock screen can draw the right number of
  dots. It is not a secret — it only tells an attacker the length.
- A 4–6 digit PIN is accepted; `1234` and friends are rejected as predictable.
- OTP codes are hashed too, and compared in constant time to avoid timing leaks.
- Failed OTP attempts are counted and the challenge expires after five minutes.
- Requesting a new code invalidates the previous one, so only the newest is valid.
- Verification failures say "incorrect or expired", never which of the two it was.
- The app locks on resume after a background timeout, with biometrics as an optional
  convenience on top of the PIN — never a replacement for it.

### Reminders

`ReminderService` schedules a notification one day before each period's due date, and
cancels it when the period settles. Everything is rescheduled on app start, so alarms
survive a reboot, an app update, or the device being switched off overnight. On Android 13+
the notification permission is requested once, in context, from Settings.

---

## SOLID Explanation

### S — Single Responsibility Principle

Every class has exactly one reason to change.

- `PaymentCalculator` computes money. It does not read the clock, the database, or the UI.
- `ScheduleService` generates periods. It does not validate names or render anything.
- `CommitteeDetailScreen` renders. It does not decide whether a member may be removed —
  that is `MemberService`'s rule.
- `db_schema.dart` is the only file in the project that contains `CREATE TABLE`.

The practical test: if you wanted to change the pot formula, you would edit
`PaymentCalculator` and nothing else. If you wanted to change the colour of the progress
bar, you would edit `app_card.dart` and nothing else.

### O — Open/Closed Principle

`PaymentFrequency` is the clearest example. Adding a fortnightly-custom rhythm means
adding one enum value and the branches it needs:

```dart
enum PaymentFrequency {
  weekly(...), biweekly(...), monthly(...), quarterly(...),
  // add: custom(...)
}
```

No screen, service, or repository changes, because nothing anywhere in the project
`switch`es on frequency in a way that would need a new case — the enum owns the date
arithmetic and the labels. The same applies to `PaymentMethod`, `CommitteeStatus`, and the
theme preference.

The `OtpSender` interface is Open/Closed in the same way: a new WhatsApp sender can be
added without modifying `OtpService` or any screen.

### L — Liskov Substitution Principle

`SharedPreferencesSettingsRepository` and the in-memory test double both implement
`SettingsRepository`. `SettingsProvider` is written against the interface and cannot tell
them apart — it works unchanged in the test. The practical payoff is `sqflite_common_ffi`:
the test suite runs the *real* SQLite repositories against an in-memory database, so the
tests exercise production code, not a mock that agrees with whatever the code does.

`AppDatabase.executor` returning a `DatabaseExecutor` is also LSP-correct: both a
`Database` and a `Transaction` satisfy it, so a repository works identically inside and
outside a transaction.

### I — Interface Segregation Principle

The interfaces are small and specific. `BiometricService` has two methods, not a general
"security service". `NotificationService` does not expose user management. A fake
notification service in a test implements three methods, not thirty.

This is also why the providers are eight separate classes instead of one
`AppProvider`. A `ChangeNotifier` that notifies on any change forces every listening
widget to rebuild when anything changes; separate providers mean the payments list does
not rebuild when the theme changes.

### D — Dependency Inversion Principle

The highest-value application of SOLID in this project. High-level policy — the business
rules in `PaymentService` — depends on the abstract `PaymentRepository`, not on
`SqlitePaymentRepository`. Both point inward toward the abstraction.

`ServiceLocator` is the only place that knows the concrete implementation exists:

```dart
locator.register<PaymentRepository>(() => SqlitePaymentRepository(locator.get()));
```

It also lives in `lib/di/`, which is where infrastructure wiring belongs, not inside a
service. This is what makes the business rules testable, and it is why `flutter test`
can run the entire committee lifecycle without mocking anything except the device
services that genuinely cannot exist on a test VM.

---

## Database Explanation

### Design decisions

**1. One relational database, not NoSQL.** A committee is a graph with real referential
integrity: payments belong to periods, periods belong to committees, turns belong to
members. SQLite gives real foreign keys, real `UNIQUE` constraints, and real
`ACID` transactions. Object storage would have to reimplement all three in application
code, badly.

**2. Denormalise the money, normalise the relationships.** `payments` store a denormalised
`amount` and a copied `due_date` taken from the member's contribution and the period at
the moment the payment was recorded. This is intentional: recorded money is a historical
fact. Relationships stay normalised, so nothing is duplicated that describes *current*
state. A committee's contribution is a single column, so there is no per-member override
to snapshot.

**3. The schedule is generated, not lazy.** Creating a committee writes all
`memberCount` periods up front rather than computing period *n* on demand. A schedule
becomes a historical record, and a committee's due dates must not shift if its start date
or frequency is edited later.

**4. Overdue is derived, never stored.** `Payment.isOverdue` is a getter comparing
`dueDate` to now. A stored `is_overdue` column would need a nightly job to stay correct
and would be wrong every time the device clock changed.

**5. `turn_number` is the rotation.** Members are not ordered by name or join date; the
`turn_number` column is their slot in the queue, protected by
`UNIQUE (committee_id, turn_number)`. The reorder sheet rewrites the whole set inside one
transaction, and if two members were ever assigned the same slot the constraint rejects it
rather than silently producing a committee where one member collects twice.

### The schema

Table and column names below are transcribed from `lib/database/db_schema.dart`, where
each table is a `const String` so a typo in a query is a compile error.

```sql
CREATE TABLE users (
  id                    TEXT PRIMARY KEY,
  full_name             TEXT    NOT NULL,
  phone_number          TEXT,
  email                 TEXT,
  pin_hash              TEXT    NOT NULL,     -- stretched+salted SHA-256, never plaintext
  pin_salt              TEXT    NOT NULL,
  is_verified           INTEGER NOT NULL DEFAULT 0,
  otp_verified          INTEGER NOT NULL DEFAULT 0,
  biometric_enabled     INTEGER NOT NULL DEFAULT 0,
  role                  TEXT    NOT NULL DEFAULT 'owner',
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until          INTEGER,
  last_login_at         INTEGER,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL
);

CREATE TABLE otp_challenges (
  id           TEXT PRIMARY KEY,
  user_id      TEXT    NOT NULL,
  channel      TEXT    NOT NULL,
  destination  TEXT    NOT NULL,
  code_hash    TEXT    NOT NULL,              -- never the plain code
  salt         TEXT    NOT NULL,
  expires_at   INTEGER NOT NULL,
  attempts     INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  consumed_at  INTEGER,
  created_at   INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE committees (
  id                  TEXT PRIMARY KEY,
  name                TEXT    NOT NULL UNIQUE,-- a committee name is unique
  description         TEXT,
  contribution_amount REAL    NOT NULL,
  frequency           TEXT    NOT NULL,       -- enum storage key
  start_date          INTEGER NOT NULL,       -- epoch millis
  duration_periods    INTEGER NOT NULL CHECK (duration_periods > 0),
  member_count        INTEGER NOT NULL CHECK (member_count > 0),
  current_turn        INTEGER NOT NULL DEFAULT 1 CHECK (current_turn >= 1),
  completed_turns     INTEGER NOT NULL DEFAULT 0 CHECK (completed_turns >= 0),
  status              TEXT    NOT NULL,
  is_demo             INTEGER NOT NULL DEFAULT 0,
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL,
  CHECK (completed_turns <= member_count)     -- cannot over-complete a committee
);

CREATE TABLE members (
  id           TEXT PRIMARY KEY,
  committee_id TEXT    NOT NULL,
  name         TEXT    NOT NULL,
  phone_number TEXT,
  address      TEXT,
  notes        TEXT,
  turn_number  INTEGER NOT NULL CHECK (turn_number > 0),
  role         TEXT    NOT NULL DEFAULT 'member',
  is_active    INTEGER NOT NULL DEFAULT 1,
  is_demo      INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  FOREIGN KEY (committee_id) REFERENCES committees (id) ON DELETE CASCADE,
  UNIQUE (committee_id, turn_number)          -- no two members share a slot
);

CREATE TABLE schedules (
  id            TEXT PRIMARY KEY,
  committee_id  TEXT    NOT NULL,
  period_number INTEGER NOT NULL CHECK (period_number > 0),
  label         TEXT    NOT NULL,             -- "October 2026", "Week of 12 Oct"
  start_date    INTEGER NOT NULL,
  due_date      INTEGER NOT NULL,
  is_closed     INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (committee_id) REFERENCES committees (id) ON DELETE CASCADE,
  UNIQUE (committee_id, period_number)        -- generation is idempotent per period
);

CREATE TABLE payments (
  id            TEXT PRIMARY KEY,
  committee_id  TEXT    NOT NULL,
  schedule_id   TEXT    NOT NULL,
  member_id     TEXT    NOT NULL,
  period_number INTEGER NOT NULL CHECK (period_number > 0),
  amount        REAL    NOT NULL CHECK (amount >= 0),  -- denormalised on purpose
  due_date      INTEGER NOT NULL,             -- copied, so history is immutable
  paid_date     INTEGER,
  status        TEXT    NOT NULL CHECK (status IN ('pending','paid')),
  method        TEXT,                         -- cash | bankTransfer | easypaisa | ...
  notes         TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  FOREIGN KEY (committee_id) REFERENCES committees (id)  ON DELETE CASCADE,
  FOREIGN KEY (schedule_id)  REFERENCES schedules  (id)  ON DELETE CASCADE,
  FOREIGN KEY (member_id)    REFERENCES members     (id)  ON DELETE CASCADE,
  UNIQUE (committee_id, member_id, period_number)       -- one payment per member per period
);

CREATE TABLE turns (
  id                TEXT PRIMARY KEY,
  committee_id      TEXT    NOT NULL,
  turn_number       INTEGER NOT NULL CHECK (turn_number > 0),
  member_id         TEXT    NOT NULL,
  period_number     INTEGER NOT NULL CHECK (period_number > 0),
  expected_amount   REAL    NOT NULL CHECK (expected_amount >= 0),   -- the pot
  collected_amount  REAL    NOT NULL DEFAULT 0 CHECK (collected_amount >= 0),
  due_date          INTEGER NOT NULL,
  status            TEXT    NOT NULL CHECK (status IN ('upcoming','active','completed')),
  completed_at      INTEGER,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  FOREIGN KEY (committee_id) REFERENCES committees (id) ON DELETE CASCADE,
  FOREIGN KEY (member_id)    REFERENCES members     (id) ON DELETE CASCADE,
  UNIQUE (committee_id, turn_number),
  UNIQUE (committee_id, member_id)               -- no member twice in the rotation
);
```

### `CHECK` constraints as business rules

Beyond the `UNIQUE` keys, seven `CHECK` constraints make invalid states physically
unrepresentable — the cheapest possible validation, because the database refuses them
even if a future caller bypasses the service layer:

| Constraint | Prevents |
| --- | --- |
| `committees.duration_periods > 0` | A committee with no periods |
| `committees.member_count > 0` | An empty committee |
| `committees.current_turn >= 1` | Turns numbered from zero |
| `committees.completed_turns <= member_count` | A committee claiming more payouts than members |
| `members.turn_number > 0` | A member with no slot in the rotation |
| `payments.amount >= 0` | Negative contributions and refunds-by-accident |
| `turns.collected_amount >= 0` | A negative pot |

Two more encode domain vocabulary directly in SQL:
`payments.status IN ('pending','paid')` and
`turns.status IN ('upcoming','active','completed')`. A typo in a status string is a
constraint violation rather than a payment that silently never shows up in a filter.

### Indexes and why they exist

| Index | Serves |
| --- | --- |
| `idx_otp_user (user_id, consumed_at)` | Find the live challenge for the current user |
| `idx_committees_status (status)` | The status filter chips and the active-committee count |
| `idx_members_committee (committee_id, turn_number)` | Roster reads, already in rotation order |
| `idx_payments_period (committee_id, period_number, status)` | The payments screen loads one period; the filter chips need `status` |
| `idx_payments_member (member_id, period_number)` | Per-member payment history and progress |
| `idx_turns_committee (committee_id, turn_number)` | "Whose turn is it?" — the hottest query in the app |

Every one of these corresponds to a query the app actually issues; the composite column
order puts the equality predicate first and the range/sort column last, which is what
lets SQLite stop scanning early. There are no speculative indexes.

### The `UNIQUE` constraints as business rules

- `committees.name UNIQUE` — two committees cannot share a name. The repository catches the
  violation and rethrows `DuplicateException`, so the user sees a sentence.
- `payments UNIQUE (committee_id, member_id, period_number)` — a member cannot pay the
  same period twice, so double-tapping "mark paid" is harmless.
- `members UNIQUE (committee_id, turn_number)` — two members cannot be given the same
  slot in the rotation. This is what physically enforces "one member, one turn".
- `turns UNIQUE (committee_id, member_id)` — a member cannot appear twice in the order.
- `schedules UNIQUE (committee_id, period_number)` — schedule generation is idempotent
  per period, so a retried generation cannot produce duplicates.

The redundancy is deliberate: a rule enforced in two places is not weaker than a rule
enforced in one.

### Transactions: the part that is easy to get wrong

Creating a committee must insert the committee, its members, its schedule, and its turns
as one unit. If it crashed after the third insert, the app would have an orphan committee
with no roster and no way to repair it.

```dart
await _database.transaction((Transaction txn) async {
  final DatabaseExecutor db = txn;
  await committeeRepository.create(committee, db);
  await memberRepository.insertAll(members, db);
  await scheduleRepository.insertAll(periods, db);
  await turnRepository.insertAll(turns, db);
});
```

The subtlety is the `DatabaseExecutor`. Repositories are written to accept an executor
and default to `database` when none is passed. If they had called `database` internally
instead, the first `await` inside the transaction would try to grab a **second** connection
while the transaction still held the write lock — a genuine deadlock, in production and in
tests. The test suite caught exactly this, which is the argument for having it.

### Migrations

`onCreate` builds the schema; `onUpgrade` applies versioned steps so an installed app
upgrades without losing data. `PRAGMA foreign_keys = ON` is enabled on every open — SQLite
ships with it **off** by default, and forgetting this silently disables every `ON DELETE
CASCADE` in the schema above.

---

## Viva Questions and Answers

**Q1. Why SQLite and not Firebase?**
A committee is a local, single-user record. The app must work with no connectivity, cost
nothing to run, and store money records that must never depend on a server being up.
SQLite also gives real transactions and constraints, which a document store would not.

**Q2. What is `AsyncValue<T>`, and why not three booleans?**
A single type built on a `LoadState` enum (`idle`, `loading`, `ready`, `failed`) holding
`data` and `error`. Booleans like `isLoading` + `items` + `error` can represent
contradictory states — loading *and* empty *because the request failed* — and the three
fields drift out of sync. One union type cannot represent a state that does not exist.
Its `loading` state also carries the previous `data`, so a refresh keeps the old list on
screen instead of flashing a spinner.

**Q3. Why `provider` and not `bloc`?**
Eight state classes, one consumer each, and debuggability matters more than event
plumbing. `provider` gives the same unidirectional flow with far less ceremony. If the app
grew complex event sourcing, `bloc` would be the better answer.

**Q4. Explain the transaction and executor problem.**
Repositories must run inside the caller's transaction or the write is not atomic. They
accept a `DatabaseExecutor` so a `Transaction` can be passed down. If a repository had
used `AppDatabase.database` internally, `sqflite` would open a second connection, the first
one still holding the write lock, and the query would block forever. The tests hung on
exactly this before the executor was threaded through.

**Q5. Why is `isOverdue` a getter instead of a column?**
It depends on today's date. A stored column would need a background job to stay correct
and would be wrong after a clock change or an app not being opened for a week. Deriving it
always keeps it true.

**Q6. Why is the payment amount denormalised onto the payment row?**
Money already recorded is a historical fact. If a member's contribution changes in June,
January's payment must still read Rs. 1,000. Recomputing historical amounts from current
state would silently rewrite history.

**Q7. Why does the schedule get generated eagerly?**
A schedule is a record. Generating all periods up front means the due dates cannot shift
later because someone edited the start date or the frequency. Lazy generation would make
past periods depend on present settings.

**Q8. Why is the committee name `UNIQUE` but the user's PIN is only in one table?**
One user exists, so `users` needs no uniqueness constraint on anything but its id. But two
committees sharing a name is a genuine user error that produces confusing records, and the
database is the right place to stop it.

**Q9. Where does validation live, and why not in the widget?**
`TextFormField` validators give immediate, friendly feedback in the widget. The
*authoritative* check lives in the service, because a service can be called from anywhere —
a screen, a notification, a test. Validating only in the UI means the rule is unenforced
the moment there is a second caller.

**Q10. How is the PIN stored?**
Stretched and salted: `hashSecret` runs 25,000 rounds of SHA-256 over the PIN with a
16-byte random salt, and `secureEquals` compares the result in constant time. The
plaintext is never written to disk or logged, and `failed_login_attempts` / `locked_until`
throttle guesses. State it honestly in a viva though: 25k rounds of a *fast* hash is
meaningfully better than a bare digest, but a real KDF such as Argon2id or PBKDF2 would be
stronger. The important architectural point is that every hash call goes through
`CryptoHelper`, so swapping the algorithm is a one-file change.

**Q11. Why does the OTP sender have two implementations?**
`OtpSender` is an interface, so the app can be demonstrated offline with
`InAppOtpSender` and run in production with `HttpOtpSender`, with no change to the service
or the UI. The composition root picks. This is Dependency Inversion with a practical
payoff, and it is why the app needs no `INTERNET` permission by default.

**Q12. How would you test payment logic?**
Against a real in-memory SQLite database using `sqflite_common_ffi`, driving the real
services and real repositories. Only the genuinely device-bound services (notifications,
biometrics) are faked. Testing against the real database catches the constraint and
transaction bugs that a mocked repository would happily let through — which is how the
deadlock and the missing-member-insert bugs were found.

**Q13. What is the difference between the per-turn pot and the total pending?**
`expectedPool` is one period's collection: `memberCount × contribution`. `totalPending` is
every unpaid period summed: `pot × (periods so far − turns completed)`. Confusing the two
is the most common arithmetic mistake in committee software, so they are separate,
separately-named fields in `DashboardStats`.

**Q14. Why use a `CustomPainter` for the chart instead of a package?**
One bar series. The painter is about sixty lines, adds no dependency, has no version
conflicts, and uses the app's own semantic colours, so it is correct in both light and
dark mode by construction.

**Q15. What would you change before a Play Store release?**
Replace the debug signing config with a real key, add a release `applicationId` suffix if
shipping a variant, add a ProGuard/R8 verification pass on a release build, add widget
tests for the create-committee flow, and — for a networked build — supply the OTP gateway
and uncomment `INTERNET`.

**Q16. Why is `MainActivity` a `FlutterFragmentActivity`?**
`local_auth` shows a BiometricPrompt, which is an Android *fragment*. A plain
`FlutterActivity` has no fragment container, so the prompt can never be attached and
biometrics silently never appear. This is the number-one cause of that bug.

**Q17. Where does "whose turn is it?" come from, and is it a stored or derived value?**
From `committees.current_turn`, a counter on the committee that starts at 1 and is
constrained to `>= 1`. The `turns` table holds the rotation: one row per member with a
`turn_number`, an `expected_amount` pot, a `collected_amount` running total, and a status
of `upcoming` / `active` / `completed`. Exactly one row is `active` at a time, and
`completed_turns` on the committee is bounded by `CHECK (completed_turns <=
member_count)` so a committee can never claim more payouts than it has members.

**Q18. Tell me about a bug your tests found, and how.**
Two.

*An inverted regex.* `Validators.pin` used `if (!_digitsOnly.hasMatch(raw))` to reject
non-digits, but `_digitsOnly` is `RegExp('[^0-9]')` — so it matches precisely the strings
that *are* valid. Every PIN in the app was rejected with "PIN must contain digits only",
which meant **registration was impossible on a real device**. `flutter analyze` was clean,
the 17 service tests all passed, and the code read correctly. `Validators.otp` had the same
inverted check, so OTP entry was broken too. What caught it was writing a test that asserts
a *valid* input returns `null` — the obvious direction, but the one people forget, because
"does it reject bad input" is the direction everybody already tests. The lesson is that
a validator needs tests in the direction that proves it is *permissive*.

*The transaction deadlock.* Repositories originally read `AppDatabase.database` internally.
Inside a service transaction that opened a second connection while the transaction still
held the write lock, so the query blocked forever and the test suite hung. The fix was to
pass a `DatabaseExecutor` down from the transaction, so both the transaction and the
repository operate on the same connection. Neither bug was findable by reading the code
carefully; one needed a test that asserts a valid input is *accepted*, and the other needed
a test that runs against a real database instead of a mock. That is the argument for
integration tests over unit tests with mocks.
