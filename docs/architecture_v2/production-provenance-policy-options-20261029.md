# Production provenance decisions awaiting approval

> Historical options, superseded for new sources by the owner's greenfield V2
> authorization and [the implemented contract](greenfield-v2-cost-architecture-20261029.md).
> No production-history recovery or legacy certification is part of that contract.

## Implemented boundary

This package only strengthens the read model. No new source schema, financial
posting, approval, migration or historical mutation is activated. Native source
repositories and PeriodLock remain authoritative. Missing governance stays
INCOMPLETE. ExactDecimal, LaborMoney and all-inclusive machine pricing remain
unchanged. The five existing cost sheets retain their names and original column
positions. Only DOI CHIEU NGUON appends two diagnostic columns.

## Evidence assessment

Material: compare movement ID and document code, farm/item/plan, destination
parcel/season/currency, persisted integer quantity units, original exact price,
amount, pricer, zero-price confirmation and occurrence timestamp. Check exact
quantity-times-original-price from units, without fetching any current price.
API replay rejects another payload for the same ID and commits movement and cost
atomically. This is an API immutability contract, not a database cryptographic
seal or an independent approval. Direct SQLite modification is not certified.

The diagnostic states distinguish missing source, mismatched source, immutable
issue without approval, recorded approval evidence, and observed void/reversal.
`priced_by` never becomes `approved_by`. Native issues do not store independent
approval/revision. A hypothetical source containing such metadata is tested as
evidence assessment only; no schema or acceptance policy for it is activated.
Void/reversal markers remain quarantined pending their approved source contract;
they do not silently remove the original cost or invent a negative posting.

Payroll: existing payroll.create/payroll.approve events identify real actors and
events. They do not bind the approved financial payload. The SHA-256 observation
fingerprint is deterministic over source identity, worker/period/currency,
allowance/bonus and allocation destination/day. It excludes payment state and
query order. It is not a persisted revision, approval token, signature or new
business identity. Native payroll extras remain INCOMPLETE. Repeated projection
keeps the same source/line idempotency key, even when an observation changes.
Cancelled/replaced payrolls remain distinct. Duplicate active worker-period-
currency identities and reused payroll-correction approved revisions quarantine
all affected entries. Correction stored signed amounts are not recalculated.

Expense: payment/settlement, already-included component, period/admin expense,
direct production, common production and unqualified are distinct diagnostic
classes. Direct/common labels are not enabled TradeDraft treatments and never
authorize a cost. They remain INCOMPLETE with no automatic allocation. THU/CHI
are reconciliation-only; THU does not become sales revenue automatically.

## Read-only legacy reconciliation

`LegacyCostReconciliation.compare` accepts an authorized offline raw-row extract,
V2 projection entries and explicit evidenced source links. It never opens the
legacy database or invokes its create/upgrade/upsert methods. It performs no
write, backfill, migration, import, inference of farm, FX or historical repricing.
It is a review library, not a new UI authorization boundary or an ingestion API.
Any future UI/CLI integration must enforce farm scope and permission to BOTH
datasets before extraction. The existing report UI/export gates are unchanged.

Links must identify a specific V2 source/line key. Date/amount equality cannot
create a link. All applicable findings are retained together: duplicate source,
ambiguous/many-to-one mapping, unknown counterpart, missing currency,
approval/version gap, date/parcel/plan/category/currency mismatch, version or
amount mismatch, noneligible V2 source, and non-exact legacy amount.

Legacy REAL stays raw diagnostic data. `double.toString()` cannot certify the
original exact amount, even for a small integer. Native production_costs has no
plan/currency/approval/version fields. A completely matched synthetic record
therefore demonstrates the comparator's conditional contract, not certification
of actual legacy rows. Farm/field identity mappings and approved exact source
evidence must be supplied for real review. No legacy amount enters V2 totals.

## Decision table — all rows require owner approval

| Issue | Option A | Option B | Impact | Recommendation | Approval required |
| --- | --- | --- | --- | --- | --- |
| Material independent approval | Compatible append-only approval event binds movement ID and exact payload digest, actor/time/version; old issue untouched | Accept existing immutable issue plus persisted pricer under explicitly approved governance policy | A needs schema/workflow/restore and lock tests; B has weaker independent evidence and cannot invent historical approval | A for new data; keep historical unresolved until evidence review | Yes, schema and recognition policy |
| Material void/reversal | Explicit append-only linked correction with own date/approval and lock checks | Keep immutable original and separately quarantine discrepancy for review | Must define stock/cost/fuel reversal consistency and original vs correction period | A after business reversal policy is approved | Yes |
| Payroll allowance/bonus version | Persist immutable approved payload version/digest and included entry IDs at approval; use existing signed adjustments after approval | Use unique approval audit event ID only after extending that event to bind the payload | Existing audit IDs alone cannot attest amounts; historical rows need original approval evidence | A; observation fingerprint remains diagnostic | Yes, schema and version identity |
| Direct production expense | Approved source document and explicit plan/parcel allocation with exact amount, currency, actors and reversal | Keep period expense and managerial reconciliation only | No automatic distribution; payment cannot be another accrual | A only for an approved new source contract | Yes, eligibility and accounts |
| Common production expense | Approved explicit allocation schedule with chosen driver and residual policy | Leave overhead outside production costing and show management comparison | Driver, timing, zero-weight, partial allocation and rounding must be decided | Owner chooses; no default area/labor/machine/revenue driver | Yes |
| includedInProduction | Reconcile immutable link to already recognized source/component | Keep existing treatment as exclusion pending stronger link evidence | Avoids adding fuel/driver/material/payment twice | A for traceability, no extra posting | Yes before changing treatment semantics |
| Legacy bridge | Evidence-backed source/field/plan/farm mapping plus original exact amount/currency/approval record, reviewed offline | Preserve legacy-only comparison with unresolved flags | Native REAL/no-currency cannot prove exact complete totals; never use current prices | A where evidence exists, B elsewhere | Yes, mappings; separate approval for any future migration |
| Previously locked snapshots | Preserve original frozen rows and digest; report new evidence limitations | Separately authorized evidence supplement with immutable reference to original close | Never rewrite old snapshot or retroactively claim stronger close certification | A now | Yes for any supplement workflow |

## Verification limits

Synthetic Dart/SQLite, workbook readback and local PeriodLock tests do not certify
Firebase authorization, native Android, multi-device offline conflict resolution,
production data quality or business policy. No production or Google Sheets data
is touched. A complete operational GO requires approved source contracts and a
separately provisioned operational acceptance environment.
