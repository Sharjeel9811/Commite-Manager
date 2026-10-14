# Committee Manager — Business Logic Documentation

This document explains the complete committee logic: how money flows, how turns work,
how payments are tracked, and what the formulas are. Use this to verify correctness.

---

## Table of Contents

1. [What is a Bachat Committee?](#1-what-is-a-bachat-committee)
2. [Core Formula](#2-core-formula)
3. [Example Walkthrough](#3-example-walkthrough-5-members--rs-10000)
4. [Payment Matrix — Who Pays When?](#4-payment-matrix--who-pays-when)
5. [Turn Rotation](#5-turn-rotation)
6. [When Does a Turn Complete?](#6-when-does-a-turn-complete)
7. [How Overdue is Calculated](#7-how-overdue-is-calculated)
8. [Committee Lifecycle](#8-committee-lifecycle)
9. [Key Business Rules](#9-key-business-rules)
10. [Edge Cases and Guards](#10-edge-cases-and-guards)
11. [Formula Reference Card](#11-formula-reference-card)

---

## 1. What is a Bachat Committee?

A **Bachat Committee** (also called a rotating savings group, chit fund, or ROSCA)
works like this:

- A fixed group of members each contributes a fixed amount every period (weekly / monthly etc.)
- After the other members have paid, the entire collected pool is handed to **one member** — their "turn"
- The next period the same thing happens, but a different member gets the pool
- This continues until every single member has received the pool once
- The committee then ends

**Nobody borrows money. Nobody earns interest. The total money that enters equals
the total money that leaves.** The committee is purely an organised savings discipline.

---

## 2. Core Formula

```
Number of periods  = Number of members
                     (one period per member so everyone gets a turn)

Pot per turn       = Contribution × (Members − 1)
                     (the collecting member does NOT pay into their own pot)

Total payments     = Members × (Members − 1) × Contribution
                     (each member pays in every period except their own)

Total collected
by all members     = Members × Pot per turn
                   = Members × Contribution × (Members − 1)
                     (same number — money in = money out, no profit)
```

---

## 3. Example Walkthrough — 5 Members, Rs 10,000

| Setup | Value |
|---|---|
| Members | 5 (Ali, Sara, Omar, Zara, Bilal) |
| Contribution per period | Rs 10,000 |
| Frequency | Monthly |
| Duration | 5 months (one per member) |
| Pot per turn | 10,000 × (5−1) = **Rs 40,000** |
| Total money through committee | 5 × 40,000 = **Rs 200,000** |

### Payment matrix

| Period | Ali pays | Sara pays | Omar pays | Zara pays | Bilal pays | Pot goes to |
|--------|----------|-----------|-----------|-----------|------------|-------------|
| 1 | — | 10,000 | 10,000 | 10,000 | 10,000 | **Ali** (Turn 1) |
| 2 | 10,000 | — | 10,000 | 10,000 | 10,000 | **Sara** (Turn 2) |
| 3 | 10,000 | 10,000 | — | 10,000 | 10,000 | **Omar** (Turn 3) |
| 4 | 10,000 | 10,000 | 10,000 | — | 10,000 | **Zara** (Turn 4) |
| 5 | 10,000 | 10,000 | 10,000 | 10,000 | — | **Bilal** (Turn 5) |

**The "—" entries are zero — the collecting member is exempt from paying their own period.**

Each member pays **4 times × Rs 10,000 = Rs 40,000 total** and receives **Rs 40,000 once**.
Net position for every member = **zero** (break even by design).

---

## 4. Payment Matrix — Who Pays When?

The code builds this matrix in `PaymentCalculator.buildPayments()`:

```
FOR each period (1 to durationPeriods):
    FOR each member:
        IF member.turnNumber == period:
            SKIP  ← this member collects this period, does not pay
        ELSE:
            CREATE payment row (member, period, amount = contributionAmount)
```

This means:
- **Total payment rows** = `members × (members − 1)` (not `members × members`)
- Every period has exactly `members − 1` payment rows
- The missing payment in each period is the one belonging to whoever collects that period

---

## 5. Turn Rotation

Each member is assigned a **turn number** (1 = collects first, N = collects last).
Turn number also equals the period number they collect.

```
Turn 1 → Member collects in Period 1
Turn 2 → Member collects in Period 2
...
Turn N → Member collects in Period N
```

The organiser decides the collection order. Members can be reordered before any
payments are recorded. After the first payment is made the order is locked — changing
it would rewrite who should have received the pot, which is a financial integrity problem.

---

## 6. When Does a Turn Complete?

A turn is marked **completed** when **every payment row for that period is paid**.

```
Condition: paidCount(period) >= totalCount(period)
         = (members − 1) payments all marked paid
```

When a turn completes:
1. The turn status changes: `upcoming → active → completed`
2. The period is marked `closed`
3. The committee's `completedTurns` counter increments
4. The next turn becomes `active`
5. If all turns are completed → committee status becomes `completed`

This is handled atomically in `TurnService.reconcile()` — it runs inside the same
database transaction as the payment that triggered it, so these two things can
never be out of sync.

### Daily committees

Daily is a supported frequency alongside weekly, biweekly, monthly, and quarterly.
Period 1 is due on the selected start date; each later period is due one calendar
day later. The committee still has one period per member, so a 14-member daily
committee runs for 14 consecutive collection days.

---

## 7. How Overdue is Calculated

**Overdue is never stored** — it is always derived at runtime from date-only values:

```dart
bool isOverdueAt(DateTime now) =>
    !isPaid && DateTime(now.year, now.month, now.day)
      .isAfter(DateTime(dueDate.year, dueDate.month, dueDate.day));
```

This means:
- A payment that was due last month and is still unpaid → **overdue**
- A payment due tomorrow and still unpaid → **pending** (not overdue)
- A payment that was paid late → shows when it was paid, no longer overdue

**Severely overdue** uses the same date-only comparison and is reached after
`AppConstants.severelyOverdueDays` (30 days).
These are shown with a stronger red colour in the UI.

---

## 8. Committee Lifecycle

```
DRAFT → ACTIVE → COMPLETED → ARCHIVED

DRAFT:     Created but not started. Members can be added/reordered freely.
ACTIVE:    Collecting. Payments are being recorded. Roster is locked once
           any payment exists.
COMPLETED: All members have received their turn. No more payments expected.
ARCHIVED:  Hidden from the main dashboard. Data is preserved.
```

The app creates committees directly as **ACTIVE** (not Draft) because:
- The creation wizard collects all members before saving
- There is no staged "build then activate" flow needed
- Going Draft → Active would be an extra step with no benefit

---

## 9. Key Business Rules

### Payment proof for online payments

Online and bank payments are recorded using the selected payment method without
opening the gallery or asking the user for a screenshot. The legacy `proof_path`
column remains nullable for database compatibility and is not required by the
current payment workflow.

### Rule 1 — Collecting member does not pay their own period
The member whose turn it is to collect **does not contribute** to that period's pot.
They receive the contributions of all other members.

This is a deliberate collector-exempt ROSCA variant: `pot = C × (N − 1)`.
The common alternative is `pot = C × N`, where the collector also contributes.

### Rule 2 — Duration always equals member count
A 5-member committee runs for exactly 5 periods so every member gets exactly one turn.

### Rule 3 — Roster locks after the first payment is marked paid
Once any payment is marked paid, the collection order cannot be changed. Changing the
order after payments exist would mean the person who collected period 1's pot
retroactively "should have" been someone else.

This is enforced by both `CommitteeDetailProvider` and `MemberService`; generated
rows always exist, so row existence is not evidence that money moved.
```dart
bool get canEditRoster => committee.isEditable && !_hasPaidPayments;
```

### Rule 4 — Turn advances automatically
When all payments in a period are marked paid, the next member's turn becomes active
automatically. The organiser does not need to manually advance the turn.

### Rule 5 — Turn and committee states are recomputed
On every reconcile, a turn is completed exactly when all `N − 1` payment rows in
its period are marked paid. The earliest non-completed turn is the only `active`
turn; every other non-completed turn is `upcoming`. Completed turns are recounted.
If a payment is unmarked, the turn reopens, and a completed committee returns to
`active`. The committee is `completed` only when every turn is completed.

### Rule 6 — Amount cannot change after payments are marked paid
The contribution amount can only be changed while zero payments are marked paid.
After any payment is marked paid, the amount is locked because historical records
already used it.

---

## 10. Edge Cases and Guards

| Situation | What happens |
|---|---|
| 2-member committee | Pot = contribution × 1 = contribution amount. Member A pays once, gets the pot; Member B pays once, gets the pot. Total each pays = 1×contribution = exactly what they receive. |
| Mark payment paid twice | Rejected with `DuplicateException`; the conditional update prevents concurrent double taps. |
| Delete committee mid-run | All members, payments, turns and periods are deleted via `ON DELETE CASCADE`. No orphaned rows. |
| App killed during payment | SQLite transaction rolls back completely. Either the payment is recorded AND the turn reconciled, or neither happens. |
| Schedule missing at startup | `ScheduleService.ensureFor()` repairs only committees with zero paid rows. A mismatch with paid history is surfaced and no rows are deleted. |
| Period count mismatch after roster change | Rebuild is allowed only with zero paid rows; `clearRows()` refuses to delete paid history. |
| One-member committee | Rejected by the wizard/service and the database schema; a zero-row period is never completed. |
| Unmark unpaid row | Rejected as a no-op with a business-rule error. |

Early collectors receive money before paying all of their own later contributions:
this is an interest-free advance. The app does not alter that ROSCA behavior; it
only flags late obligations through overdue status.

---

## 11. Formula Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│              COMMITTEE MANAGER FORMULA REFERENCE                │
├─────────────────────────────────────────────────────────────────┤
│  Pot per turn          = contribution × (members − 1)           │
│                                                                  │
│  Payments per period   = members − 1  (recipient is exempt)     │
│                                                                  │
│  Total payment rows    = members × (members − 1)                │
│                                                                  │
│  Total periods         = members  (one per person)              │
│                                                                  │
│  Each member pays      = contribution × (members − 1)           │
│                          (skips their own period, pays all rest) │
│                                                                  │
│  Each member receives  = contribution × (members − 1)           │
│                          (same as they paid — break even)        │
│                                                                  │
│  Net position          = 0 for every member                     │
│                                                                  │
│  Total through system  = members × contribution × (members − 1) │
├─────────────────────────────────────────────────────────────────┤
│  EXAMPLE: 6 members, Rs 5,000/month                            │
│  Pot per turn  = 5,000 × 5         = Rs 25,000                 │
│  Each pays     = 5,000 × 5 months  = Rs 25,000 total           │
│  Each receives = Rs 25,000 once    = net zero                  │
│  Duration      = 6 months                                       │
│  Total payments= 6 × 5             = 30 payment rows           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Verification Checklist

Use this to manually verify the app is working correctly:

- [ ] Create a 4-member committee with Rs 10,000 contribution
  - Expected pot per turn: Rs 30,000
  - Expected total payments matrix: 12 rows (4 × 3)
  - Each period should have exactly 3 payment rows (not 4)

- [ ] Mark all 3 payments in Period 1 as paid
  - Period 1 should close automatically
  - Turn 1 member should show "Received" status
  - Committee `completedTurns` should increment to 1
  - Turn 2 should become `active`

- [ ] Unmark one payment in Period 1
  - Period 1 should reopen
  - Turn 1 should go back to `upcoming`/`active`
  - Committee `completedTurns` should decrement back to 0

- [ ] Mark all periods as paid for all 4 members
  - Committee status should change to `Completed`
  - Dashboard should show 0 active committees, 1 completed
  - All 4 turns should show `completed`

- [ ] Verify the collecting member has no payment row in their own period
  - Open Period 2 — the member with Turn 2 should NOT appear in the payment list
  - They should appear in all other 3 periods
