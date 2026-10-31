# Machine allocation by minute — approved option A

## Authority and units

Machine shift rates are all-inclusive. Operating time, idle time, and visit
weights are integer **minutes**. The journal accepts operating minutes and idle
minutes with a starting timestamp at minute precision; the ending timestamp is
derived from their sum. No half/quarter-shift or fractional-shift input is used.
Existing meter readings retain their physical meter unit; they are not weights.
Historical planning budgets and historical source rows are not converted.

Keep the existing money policy:

1. `total = rate.cost(run.minutes)` uses `LaborMoney.fraction` with the immutable
   rate's amount, standard minutes, scale and `halfUp`/`down` rounding.
2. `LaborMoney.allocate(total, planMinutes, run.minutes, scale)` distributes
   the rounded total with largest remainders, stable first-visit plan order,
   including the unallocated-time bucket. Do not round visits independently.
3. VND and LAK remain separate; no FX conversion or mixed-currency totals.

For 480 minutes at 800000 VND, visits A240/B240 produce 400000 per plan.
For 1 VND per 3 minutes with A1/B1/unallocated1, the historical ERP result
remains A1/B0/unallocated0 VND. Money and unallocated minutes are different
measurements; the report must expose both.

## Compatible storage

No SQLite DDL, schema version, table, migration or historical-row rewrite.
`machine_runs_v1.body` optionally adds an ordered `segments` list of existing
`MachineAllocation` objects (`planId`, integer `minutes`, optional `taskId`).
`allocations` remains one aggregate per production plan in first-visit order.
The database primary key `(source_id, plan_id)` and all cost calculations remain
unchanged. A120/B240/A120 is stored as three ordered visits with aggregates
A240/B240. Multiple visits to the same parcel through different plans remain
distinct plans. The parcel relation is resolved through the production plan.

Validation rejects missing/blank plans, nonpositive minutes, mismatched
aggregates, more than 1440 visits, and aggregate minutes exceeding operating
minutes. The existing maximum gross interval is 1440 minutes, so at one minute
minimum per visit the technical visit limit is consistent with the source.
Plan, currency, date, worker/machine/task-resource checks apply to every visit,
including visits whose task IDs differ within the same plan.

Rows without `segments` decode exactly as before and omit the new key when
serialized. Their visit order is unknown, not reconstructed from aggregates.
The backup format and accounting closing-table set/digests are unchanged.
New restore checks verify segment/aggregate consistency and task references;
historically closed plans need not become active to be restored.

New clients are required to display ordered visits. Older clients do not
understand that detail; no claim is made that an old client can edit it safely.
Existing approved records are immutable through the repository API. Corrections
retain the original run/audit via void plus a new run ID. Include the original
ID in the correction reason/new note for review; there is no automatic
replacement-chain schema or historical conversion in this change.

## Reports and Sheets handoff

Both MachineReport and Report20 include:

- `PHAN BO CA MAY ERP`: one row per run/plan, approved money, currency, run and
  plan identities/codes, parcel identity/code, operating and allocated minutes,
  rate ID/revision/amount/standard minutes/rounding policy, approval state and
  run revision, entry/approval actor/time and audit provenance when available.
  Remainder minutes/money occur once per run, including runs with no allocation.
- `LUOT CHUYEN MAY ERP`: every ordered visit and task ID with its aggregate
  cost-source reference. Money is not repeated per visit. Old runs are clearly
  marked as historical aggregates with unknown visit order.

Exact amounts in these two sheets are text, including amounts beyond Excel's
15-digit precision. They are ERP snapshots, not Sheets recalculations. Import
requires a separately reviewed mapping; the Google Sheets workbook is not
modified by this implementation. Its previous per-row-rounding formulas must
not override these ERP amounts. The sheet layout is not a blind-paste match to
the existing Google Sheets columns.

Report20's journal lists all parcel codes rather than the first parcel only;
the dedicated sheets preserve the plan/parcel/visit relationships losslessly.
Machine operating/idle durations in these exports use minutes; production
plan machine actuals also use minutes. Labor units retain their own policy.
All-inclusive machine costs remain the production-cost source; fuel,
maintenance, driver wages included in the rate, payments and legacy costs
are not added again. ProductionCostSummary remains a payment-document view,
not a replacement for the production-plan incurred-cost report.

Machine trace reads use the same live authorization, machine visibility and
financial permissions as existing cost reads. Trace labels can include closed
plans linked to visible runs, allowing historical exports to retain codes.
Report20 adds supplementary machine audit reads outside `snapshot.tables` so
existing frozen period digests and backup validators are preserved. For a closed
snapshot audit reads stop at its closing timestamp. These audit fields are
explicitly supplementary and are not newly certified by historical digests.
Missing audit/labels remain blank/unavailable; no identity or approval is invented.

## Approval, retry, locking and limits

Add-run retry retains its operation ID while the dialog remains open: same ID
and identical body is a no-op; different content is rejected. Duplicate approval
is rejected by status/revision; no duplicate cost is created. Creation,
approval, plan costs and actor audit stay transactional. The new visit fields
are inside the same guarded source body.

SQLite PeriodLock triggers continue to reject insert/update/delete for closed
dates, including changes to costs and voiding approved runs. Late delivery
after this local database knows the lock is rejected atomically. A disconnected
device cannot know a remote lock that it has not received. This work does not
invent a distributed lock authority or a new machine cloud sync queue.
Native multi-device/offline E2E remains a separate integration acceptance gate.

No production Sheets write, data migration, Firebase change, commit, push,
deployment, dependency change, or production database access is required.
