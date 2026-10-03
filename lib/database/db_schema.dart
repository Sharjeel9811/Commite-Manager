/// Every SQL statement in the project lives in this file.
///
/// Centralising the schema has two concrete benefits:
///  1. Referential integrity rules are visible in one screen.
///  2. A typo in a table name is impossible — the strings are constants.
class DbSchema {
  const DbSchema._();

  // ------------------------------------------------------------------ Tables

  static const String users = 'users';
  static const String otpChallenges = 'otp_challenges';
  static const String committees = 'committees';
  static const String members = 'members';
  static const String schedules = 'schedules';
  static const String payments = 'payments';
  static const String turns = 'turns';

  static const List<String> allTables = <String>[
    users,
    otpChallenges,
    committees,
    members,
    schedules,
    payments,
    turns,
  ];

  // ------------------------------------------------------------------- Users

  /// The single local account. `pin_hash`/`pin_salt` hold a stretched, salted
  /// SHA-256 — the plaintext PIN is never written to disk.
  ///
  /// `pin_length` is stored so the lock screen can draw the right number of
  /// dots. Without it the pad has to guess and a 4-digit PIN looks unfinished,
  /// which reads to the user as "the app wants 6 digits".
  static const String createUsers =
      '''
CREATE TABLE $users (
  id                    TEXT PRIMARY KEY,
  full_name             TEXT    NOT NULL,
  phone_number          TEXT,
  email                 TEXT,
  pin_hash              TEXT    NOT NULL,
  pin_salt              TEXT    NOT NULL,
  pin_length            INTEGER NOT NULL DEFAULT 4,
  preferred_otp_channel TEXT    NOT NULL DEFAULT 'email',
  is_verified           INTEGER NOT NULL DEFAULT 0,
  otp_verified          INTEGER NOT NULL DEFAULT 0,
  biometric_enabled     INTEGER NOT NULL DEFAULT 0,
  role                  TEXT    NOT NULL DEFAULT 'owner',
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until          INTEGER,
  last_login_at         INTEGER,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL
)''';

  /// OTP challenges. Only the *hash* of the code is stored, never the code.
  static const String createOtpChallenges =
      '''
CREATE TABLE $otpChallenges (
  id           TEXT PRIMARY KEY,
  user_id      TEXT    NOT NULL,
  channel      TEXT    NOT NULL,
  destination  TEXT    NOT NULL,
  code_hash    TEXT    NOT NULL,
  salt         TEXT    NOT NULL,
  expires_at   INTEGER NOT NULL,
  attempts     INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  consumed_at  INTEGER,
  created_at   INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES $users (id) ON DELETE CASCADE
)''';

  static const String createOtpIndex =
      'CREATE INDEX idx_otp_user ON $otpChallenges (user_id, consumed_at)';

  // -------------------------------------------------------------- Committees

  static const String createCommittees =
      '''
CREATE TABLE $committees (
  id                    TEXT PRIMARY KEY,
  name                  TEXT    NOT NULL UNIQUE,
  description           TEXT,
  contribution_amount   REAL    NOT NULL,
  frequency             TEXT    NOT NULL,
  start_date            INTEGER NOT NULL,
  duration_periods      INTEGER NOT NULL CHECK (duration_periods > 0),
  member_count          INTEGER NOT NULL CHECK (member_count > 0),
  current_turn          INTEGER NOT NULL DEFAULT 1 CHECK (current_turn >= 1),
  completed_turns       INTEGER NOT NULL DEFAULT 0 CHECK (completed_turns >= 0),
  status                TEXT    NOT NULL,
  is_demo               INTEGER NOT NULL DEFAULT 0,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL,
  CHECK (completed_turns <= member_count)
)''';

  static const String createCommitteeIndex =
      'CREATE INDEX idx_committees_status ON $committees (status)';

  // ----------------------------------------------------------------- Members

  /// `UNIQUE (committee_id, turn_number)` is what physically prevents two
  /// members from being given the same slot in the rotation.
  static const String createMembers =
      '''
CREATE TABLE $members (
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
  FOREIGN KEY (committee_id) REFERENCES $committees (id) ON DELETE CASCADE,
  UNIQUE (committee_id, turn_number)
)''';

  static const String createMemberIndex =
      'CREATE INDEX idx_members_committee ON $members (committee_id, turn_number)';

  // -------------------------------------------------------------- Schedules

  static const String createSchedules =
      '''
CREATE TABLE $schedules (
  id            TEXT PRIMARY KEY,
  committee_id  TEXT    NOT NULL,
  period_number INTEGER NOT NULL CHECK (period_number > 0),
  label         TEXT    NOT NULL,
  start_date    INTEGER NOT NULL,
  due_date      INTEGER NOT NULL,
  is_closed     INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (committee_id) REFERENCES $committees (id) ON DELETE CASCADE,
  UNIQUE (committee_id, period_number)
)''';

  // ---------------------------------------------------------------- Payments

  /// This is the data-integrity heart of the app:
  ///  * UNIQUE (committee_id, member_id, period_number) => a member can be
  ///    recorded as paying a given period exactly once.
  ///  * CHECK (amount >= 0) => no negative contributions.
  ///  * Foreign keys with ON DELETE CASCADE => deleting a committee removes
  ///    its members, periods, payments and turns atomically.
  static const String createPayments =
      '''
CREATE TABLE $payments (
  id            TEXT PRIMARY KEY,
  committee_id  TEXT    NOT NULL,
  schedule_id   TEXT    NOT NULL,
  member_id     TEXT    NOT NULL,
  period_number INTEGER NOT NULL CHECK (period_number > 0),
  amount        REAL    NOT NULL CHECK (amount >= 0),
  due_date      INTEGER NOT NULL,
  paid_date     INTEGER,
  status        TEXT    NOT NULL CHECK (status IN ('pending','paid')),
  method        TEXT,
  notes         TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  FOREIGN KEY (committee_id) REFERENCES $committees (id) ON DELETE CASCADE,
  FOREIGN KEY (schedule_id)  REFERENCES $schedules  (id) ON DELETE CASCADE,
  FOREIGN KEY (member_id)    REFERENCES $members     (id) ON DELETE CASCADE,
  UNIQUE (committee_id, member_id, period_number)
)''';

  static const String createPaymentPeriodIndex =
      'CREATE INDEX idx_payments_period ON $payments (committee_id, period_number, status)';

  static const String createPaymentMemberIndex =
      'CREATE INDEX idx_payments_member ON $payments (member_id, period_number)';

  // ------------------------------------------------------------------- Turns

  /// The rotation. `UNIQUE (committee_id, turn_number)` and
  /// `UNIQUE (committee_id, member_id)` together make it impossible for one
  /// member to appear twice in the order.
  static const String createTurns =
      '''
CREATE TABLE $turns (
  id                TEXT PRIMARY KEY,
  committee_id      TEXT    NOT NULL,
  turn_number       INTEGER NOT NULL CHECK (turn_number > 0),
  member_id         TEXT    NOT NULL,
  period_number     INTEGER NOT NULL CHECK (period_number > 0),
  expected_amount   REAL    NOT NULL CHECK (expected_amount >= 0),
  collected_amount  REAL    NOT NULL DEFAULT 0 CHECK (collected_amount >= 0),
  due_date          INTEGER NOT NULL,
  status            TEXT    NOT NULL CHECK (status IN ('upcoming','active','completed')),
  completed_at      INTEGER,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  FOREIGN KEY (committee_id) REFERENCES $committees (id) ON DELETE CASCADE,
  FOREIGN KEY (member_id)    REFERENCES $members     (id) ON DELETE CASCADE,
  UNIQUE (committee_id, turn_number),
  UNIQUE (committee_id, member_id)
)''';

  static const String createTurnIndex =
      'CREATE INDEX idx_turns_committee ON $turns (committee_id, turn_number)';

  // --------------------------------------------------------------- Migrations

  /// SQL applied when upgrading from version 1 to version 2.
  ///
  /// Existing installs get the new column with the minimum PIN length, because
  /// nothing recorded the real one. A 4-digit guess is the safer default: the
  /// user can still enter up to 6 digits, they simply are not told in advance
  /// how many are needed.
  static const List<String> upgrade1to2 = <String>[
    'ALTER TABLE $users ADD COLUMN pin_length INTEGER NOT NULL DEFAULT 4',
    // v2 also recorded which channel the user asked for, at a time when SMS and
    // email were both options. The default is kept as 'sms' here because that is
    // what the v2 column was created with; `OtpChannel.fromStorage` maps it to
    // email, since SMS no longer exists.
    "ALTER TABLE $users ADD COLUMN preferred_otp_channel TEXT NOT NULL DEFAULT 'sms'",
  ];

  // ---------------------------------------------------------------- Lifecycle

  /// Executed in order, inside one transaction, on first launch.
  ///
  /// Order matters twice over:
  ///  * a table must exist before the index that references it;
  ///  * a table must exist before another table's FOREIGN KEY can point at it.
  static const List<String> createStatements = <String>[
    createUsers,
    createOtpChallenges,
    createCommittees,
    createMembers,
    createSchedules,
    createPayments,
    createTurns,
    createOtpIndex,
    createCommitteeIndex,
    createMemberIndex,
    createPaymentPeriodIndex,
    createPaymentMemberIndex,
    createTurnIndex,
  ];
}
