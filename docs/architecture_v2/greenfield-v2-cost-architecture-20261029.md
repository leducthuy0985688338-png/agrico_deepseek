# Greenfield V2 production cost contract

> Source-governance checkpoint, extended by Approval B native integration.
> The source, money and allocation contracts below remain unchanged. Statements
> about direct repository approval describe the primitive, not a permitted UI or
> application bypass. The current approval boundary is specified next.

## Current Approval B boundary (audit 2026-10-31)

The official V2 bootstrap installs NativeApprovalGuard before module routes open.
Native repositories retain their money/posting algorithms, but approved source,
ledger and integration-link writes require the transaction-bound execution lease
issued by SqliteDocumentApproval through NativeApprovalRepository. A lease is not
an authority, cannot survive a backup, and is removed before transaction commit.
The request, native effects and decision audit commit or roll back together.

DocumentApprovalPolicy and native permission floors govern both independent and
explicit conditional self approval. Material issues, machine runs, field work and
direct expense may self approve only under a verified active policy, explicit
self capability, exact currency cap and sufficient conflict/link evidence.
Payroll, purchase, common allocation, settlement, cash and corrections require
an independent actor. Native source creation and policy authorship are separate
identities. No policy cap, UID or beneficiary binding is inferred from admin.

Finance creates an immutable pending source, not an early cash-ledger row. Only
approval atomically posts finance_documents_v2; rejection posts nothing. Posted
cash is immutable and full-amount reversal is a separately approved, uniquely
linked document. Requests v3 bind source identity/revision/digest and policy
version; resubmission never fabricates a new financial document revision.

Policy drafts are published by the authenticated manager and activated by another
explicitly provisioned actor through server callables. SQLite is not the trusted
policy authority. Missing/revoked authority or unresolved beneficiary mapping
fails closed. Generic account administration cannot bootstrap cloud authority.
A policy-only actor can inspect/activate via Settings and the existing integration
workspace without payroll/cash/report read access; viewing policy does not grant
proposal, limit-management or posting rights. Multi-device draft distribution is
not certified by this local workflow and still needs an explicit integration plan.

A live snapshot carrying the B marker requires native B approval proof in the
projection. Existing locked snapshots are not rewritten or retroactively given
that marker. The 27-sheet export and exact-text money contracts remain unchanged.
The former read-only legacy comparator remains diagnostic/test-only; no history
recovery or legacy ingestion is introduced.


## Authority and data path

AGRICO has test data only. No production legacy migration, historical provenance
recovery or legacy ingestion is implemented. Existing test rows are not deleted,
repriced or silently approved. Fresh sources carry governance from creation.

UI → application service/live authorization → repository interface → SQLite
repository/transaction → native source plus approval metadata → transactional
IntegrationSnapshot → ProductionCostProjection → UI and five exact-text sheets.

Each amount has one native source: inventory issue/material snapshot, personnel
payroll and signed adjustment, machine approved snapshot, or Trade expense.
Finance THU/CHI remains payment reconciliation. All-inclusive machine fuel and
driver components remain excluded from additional costing. No second journal or
new parallel expense document is created.

## Schema migration 1

Idempotent additive DDL runs through existing module createSchema initialization:

- production_source_versions_v2: farm/type/source composite identity, persisted
  lifecycle revision 1 at creation and 2 at approval, business day, canonical
  SHA-256 payload digest, creator/time, state, approver/time. It stores no money.
- production_source_audit_v2: immutable create/approve event, revision,
  actual actor/time and digest, unique source/revision.
- production_expense_policies_v2: one immutable explicit allocation proposal
  per native Trade expense, driver/base units/money scale/evidenced weights,
  native source digest. No new expense amount is stored here.
- production_expense_costs_v2: approved allocation children, exact amount text,
  farm/plan/parcel/currency, unique policy/plan. These are the native expense's
  allocation snapshots, analogous to existing labor/machine/material children.
- production_cost_schema_v2: explicit applied migration marker version 1.

No existing table is dropped, cleared or backfilled. SQLite user_version is not
repurposed; this feature has its own idempotent marker. Existing test rows lacking
these records remain unresolved in the projection. New fixtures use native write
workflows; no fabricated approval/revision is inserted into existing data.

SQL triggers protect audit, identity, approved state and allocation immutability.
PeriodLock guards metadata, policies and children using persisted business dates.
Confirmed atomic restore removes only these storage guards in its transaction,
validates restored bindings/allocations and reinstalls guards; rollback restores
the prior state. Normal operations cannot use restore as a write bypass.

## Workflows

Material issue creation retains its authorized warehouse operation: stock,
movement, exact cost snapshot and creation metadata commit atomically. This is
operational stock posting, not automatic cost approval. A distinct cost approval
action requires inventory.price and finance.approve, farm-wide report access,
the reviewed revision, unchanged source digest and an eligible destination.
Real creator comes from live scope; unscoped fixture commands supply their price
actor explicitly. The pricer is never inferred to be the cost approver.

Payroll creation binds all approved-base financial fields, allowance/bonus,
destination/day and included entry IDs/amounts. Native approvePayroll persists the
approval event/digest. Subsequent corrections keep their existing payroll
approved_revision sequence and signed child amounts, and bind their own approved
payload digest. That business sequence differs from the metadata lifecycle
revision, so exports expose both Source revision and Approved payload version.
Payments, active line reservations and cancellation status do not reprice the
original approved payload. Cancelled source status still controls eligibility.

Trade expense creation/post seals its native payload with real create/post
actors. directProduction requires an explicit native plan. commonProduction
requires an explicit allocation driver and plan weights. Neither classification
alone recognizes cost. A proposal references a posted, digest-verified native
expense; approval requires finance.approve and live farm-wide read authority.
No child cost is created before that approval. Source, proposal, destinations and
currency are checked again inside the transaction; a last access check rolls
back all writes after revocation. Replays return the same result without adding
another source, approval or allocation.

The default V2 costs menu opens the unified report for authorized users. Existing
restricted cash views remain payment views, not another official cost source.
The report shows source/actor/revision/digest and driver/base/precision/weights
before approval. No driver is preselected. New labels preserve VI/EN/LO.

## Allocation contract

Drivers are direct, area, machineMinutes, laborMinutes and approvedWeights.
Only direct uses one explicit destination with unit/base 1. Common costs have no
default driver, scale, denominator or destination. Area units are millionths of
m²; machine/labor units are integer minutes; custom weight units are explicit.
These are entered measurement snapshots with mandatory evidence references and
approval. No geometry authority is inferred and no measurement is automatically
recomputed from current master data or an unapproved estimate.

Base units must be positive and at most 9007199254740991. Up to 1000 unique plans
are supported, each with positive units and evidence. Sum(weights) must not exceed
base. Plan/farm/parcel/currency/dates/active status must match. A zero base is
rejected, including for zero money. Missing or unapproved configuration stays
INCOMPLETE/PENDING instead of choosing a driver or manufacturing a zero.

The source's already billed/approved exact total is allocated with unchanged
LaborMoney.allocate, using the explicitly approved money scale 0–6. It is never
rounded again. Largest remainders follow stored weight order, including the
unallocated share. Partial allocation is visible and blocks a complete total and
closing. Integer units/ExactDecimal/BigInt handle all money; no FX or double money
calculation is added. Native Trade retains its existing whole VND/LAK billing and
safe bound 9007199254740991; machine A's larger/fractional contract is unchanged.

Immutable proposals/approved configurations are not edited in place. Incorrect
proposals may be cancelled via the native expense void action and reissued with
a new source identity. Same-open-period cancellation of partial allocation nets
only the recognized parts to zero and removes the unallocated pending charge.
Cross-period cancellation of a partial allocation is rejected rather than
silently restating an incomplete source period. A future cross-period reallocation
workflow requires an explicit business decision; it is not inferred here.

Native void of a fully allocated expense creates a separately sealed correction
payload including actual void day/revision/status. Projection emits negative
allocations in that correction month with its real actor/time and original
reference; original child rows remain unchanged. Neither formatted dates nor an
old approval alone can certify a tampered reversal. Closed periods stay guarded.

## Projection, export and integrity

Source/line identity is stable across retries. Native digest, source audit,
destination, amount/currency and approved allocation snapshots must reconcile.
Missing versions, changed payloads, duplicate identities or invalid policies
fail closed. VND and LAK remain separate at detail/plan/parcel/month levels.
Missing totals remain blank with INCOMPLETE; covered-empty sources can show zero.

Report20 retains 27 sheets. The five cost sheets keep their names. The first
detail sheet retains its original 23 columns and appends approved digest,
approved payload version, driver, weight, base and evidence (29 columns total).
DOI CHIEU NGUON retains its 17-column diagnostic contract. Money stays text exact,
not Excel formulas. Machine allocation/visit headers and amount algorithms stay
unchanged. Consumers must accept appended columns or resolve by header.

Backup/preflight/activation validate native payload bindings and expense children;
closing checks unapproved active sources and unallocated expenses. New closing
snapshots carry an explicit source-coverage certificate. Previous test snapshots
are not rewritten or retroactively certified.

## Legacy disposition and acceptance limits

No legacy source is removed in this package. main defaults to MyApp/V2;
MyApp.legacy still registers V1 providers. MachineProvider/EmployeeProvider/
FuelProvider still call legacy sync writers; old season screens still call old
cost screens. Those paths require replacement and regression before deletion.
The previous legacy comparator has a test consumer only and is not imported by
the V2 app; it is a retirement candidate, not a new authority or ingestion path.
No new legacy recovery features are added.

Material DTOs and REAL shadow fields still have existing UI/test consumers.
Canonical V2 amount_text/unit_price_text calculations are exact; the remaining
shadow conversion/display is not an alternative costing algorithm. Removing
these fields and retiring the explicit V1 entry should be a focused follow-up
with caller migration, not a blind deletion or a historical recovery project.

Local SQLite/Flutter/export tests do not certify Android native, Firebase,
distributed offline lock authority, full repository CI/release gates or real
operational configuration. Driver/evidence/precision and approval-role separation
are explicit owner configuration decisions before production activation.
