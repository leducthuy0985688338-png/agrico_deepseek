# Production cost source contract — read-only unification

> Historical read-only checkpoint. New V2 sources follow
> [the approved greenfield contract](greenfield-v2-cost-architecture-20261029.md).
> Material/payroll governance and native expense allocation are now implemented.
> This document's earlier BLOCKED decisions do not disable those new workflows.

## Boundary

`ProductionCostEntry` is a projection over saved V2 source snapshots, not a
second cost ledger. No schema, posting, migration, historical repricing or
period-close policy changes are introduced. The machine minute policy and its
two existing export sheets remain unchanged.

Data path: existing source repositories and approvals → IntegrationRepository
transactional snapshot → ProductionCostProjection → parcel/plan/currency UI
and five exact-text export sheets. Existing IntegrationService farm-wide,
per-permission live read/export gates remain the only entry point to that UI.

## Source mapping

| Source type | Native rows | Recognition and identity | Limit |
| --- | --- | --- | --- |
| labor | personnel_entries_v1 + production_labor_costs_v1 | approved entry, stored allocated amount, key entry/plan | creation/approval audit required; machine-included wages excluded |
| payrollExtra | personnel_payrolls_v1 | approved allowance+bonus only, original extra_cost_day/adjustment_plan_id | native payroll has no revision: incomplete under this contract; never use net pay |
| payrollCorrection | personnel_payroll_adjustments_v1 + costs | approved_revision, signed saved allocation, original payroll reference | no recalculation of earnings or source prices |
| material | production_material_costs_v2 + inventory_movements_v2 | saved issue amount and matching movement, key movement | native issue lacks revision/separate approval audit: incomplete, not assigned a fake revision/approver |
| machine | machine_runs_v1 + machine_costs_v1 | approved source, stored amount, key run/plan | all-inclusive; no new visit-level money |
| sale / saleReversal | trade_documents_v1 snapshot lines | posted billed snapshot per line, separate void_day reversal | sales minus incurred cost is not inventory-matched accounting profit |
| tradeExpense | trade_documents_v1 body expenseTreatment | periodExpense and includedInProduction excluded from production | no approved direct/common production allocation contract exists; unknown treatment is incomplete |
| cash | finance_documents_v2 CHI | reconciliation only | cash is never assumed to be production accrual |

Production issues without their cost projection are quarantined. Unlinked stock
issues with no production destination are not automatically production costs.
Fuel movement identity links exclude machine components. Payments, purchases,
payroll settlements, driver wages included in a shift and legacy rows are never
added as a second copy of a recognized production source. Independent source IDs
on the same date/parcel remain independent.

## Contract and quality states

Entries expose source type/ID/revision/line, plan and parcel, category, exact
amount and scale, VND/LAK, business date/month, native status, creator/approver
and timestamps, correction/audit references, and an identity key encoded from
source type/ID/line. Missing source metadata stays null; no fictional zero or
approval is synthesized.

Eligibility distinguishes eligible, pending, incomplete, excluded and voided.
Duplicate identity quarantines both occurrences, including conflicting values.
Missing source tables differ from known empty tables. Null category totals are
shown as insufficient data, not zero; a complete covered source with no activity
can show a genuine zero. Unknown currency blocks both currency summaries.
Unknown destination/date remains in reconciliation and does not silently acquire
the selected month or a parcel. Nonzero unallocated labor/machine money remains
explicit and blocks a falsely complete parcel total.

Complete plan and parcel aggregates use ExactDecimal/BigInt only. No binary
floating-point additions, FX, independent money rounding or spreadsheet source
recalculation. Revenue and profit are unavailable when their required scope is
incomplete. Source prices and signed correction snapshots are never recomputed.

## Closing and provenance

PeriodLock and the native closing digest/table set remain unchanged. Historical
frozen amounts continue to be read from their frozen source tables. New optional
snapshot properties carry source audit and live table availability outside
`snapshot.tables`; they do not rewrite or retroactively certify old digests.
Supplementary audit reads stop at the closing timestamp for a frozen report.
Audit events without the same farm provenance are not accepted.

Old frozen snapshots did not certify table availability. Their new unified
totals are marked incomplete instead of claiming a missing source was empty.
The previous snapshot report is retained as a compatibility view and explicitly
points readers to the new source reconciliation sheets.

No new closing gate is silently imposed: native closing still follows its
existing contract. A native locked period therefore does not imply the new
stronger cost-provenance contract is complete. This distinction is visible in
the new status/locked columns.

## UI and exports

The integrated report overview exposes expandable parcels and plans with VND
and LAK columns, four cost categories, incurred cost, posted sales and their
difference. Missing data, no activity, pending sources, approval and locked
period are distinct. The original payment-document report remains a cash view.

Report20 now has 27 worksheets: its existing 22 (including both machine sheets)
plus CHI PHI SAN XUAT ERP, GIA THANH THEO KE HOACH, GIA THANH THEO LO DAT,
DOANH THU LOI NHUAN and DOI CHIEU NGUON. The first contains eligible cost
entries; reconciliation retains pending/incomplete/excluded/voided sources.
Amounts and all official totals in the five new sheets are exact text supplied
by ERP, never Excel/Sheets formulas. Blank totals have explicit quality status.

## Decisions deliberately blocked

1. Material posting: approve a provenance policy for immutable issues, or a
   separately approved compatible audit/revision workflow; do not treat priced_by
   as an independently approved_by by inference.
2. Payroll additions: approve a native immutable version identity or a compatible
   revision mechanism. Do not assign revision zero to historical rows.
3. Other direct/common production expenses: approve eligibility, plan/parcel
   assignment, approval, allocation basis and reversal rules before any posting
   implementation or schema extension.
4. Legacy: its cost models use double/REAL and lack reliable currency/approval
   metadata. It remains available in compatibility paths but is not silently
   converted, imported or added to V2 totals. Owner reconciliation is required
   before treating the V2 report as comprehensive across legacy data.
5. Accounting profit: approve inventory/COGS matching and overhead treatment
   before renaming sales-minus-incurred-cost as final accounting profit.
6. Distributed offline lock authority remains absent; SQLite guards protect a
   local database that already knows its lock. Native multi-device/Firebase E2E
   requires a separately provisioned acceptance environment.

Review is possible without these decisions; comprehensive production costing
and production operation are not certified by this read-only implementation.

## Provenance review extension

Material source equality now checks the full persisted identity/destination,
quantity units, original exact price/amount and pricing metadata. Payroll
observations expose deterministic fingerprints without assigning a durable
revision. Active payroll business identity and correction-version collisions
quarantine all affected entries. THU and CHI remain reconciliation-only.
DOI CHIEU NGUON appends evidence state and observation fingerprint after its
original 15 columns; no existing column is shifted and no new cost is authorized.
The read-only legacy comparison library requires explicit evidenced mappings;
it does not read/import legacy data automatically or mix it into V2 totals.

See [policy options](production-provenance-policy-options-20261029.md) for the
source checks, exact comparison rules, decision table and acceptance limits.
