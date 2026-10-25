# Company catalog — A04

> Production cutover update (2026-10-25): the dated legacy field/outbox integration notes below are superseded by [Native V2 production](../architecture_v2/native-production-cutover-20261025.md). New V2 production seasons and material costs use V2 parcel identities and one SQLite transaction.


## Scope

The authenticated Settings route provides units, crops, machines, workers, materials, task types, suppliers, income categories and expense categories. The authoritative catalog and its business projections are stored in local SQLite. Catalog synchronization has separate transport, verification and conflict-handling components; do not infer that other V2 business modules are cloud-synchronized.

## Rights

- `catalog.view`: read the farm's masters.
- `catalog.manage`: create/edit masters and resolve suggestions.
- `catalog.request`: submit suggestions and read one's own suggestions.
- Explicit denied permissions take precedence. Sessions are checked again within writes, including before transaction commit. No farm crossing is permitted.
- Field editing, work entry and inventory movement permissions alone do not permit master registration. The legacy reconciliation import requires catalog management.

## Persistence and invariants

`company_catalog_entries_v1`, `company_catalog_requests_v1`, `company_catalog_audit_v1` and `company_catalog_bootstrap_v1` form one optional backup group. Partial groups are rejected. Restoring a pre-A04 backup clears live catalog tables, allowing the restored business snapshots to be adopted subsequently.

New user-facing catalog entries receive automatically allocated codes in the same SQLite transaction as creation. Prefixes are DVT (unit), CT (crop), MAY (machine), NS (worker), VT (material), CV (task type), NCC (supplier), DMTHU (income category), and DMCHI (expense category). Sequences are farm- and kind-scoped; rollback does not consume a code, and retained historical codes are considered when choosing the next number. Caller-provided codes are rejected by the dedicated service.create path. Historical imports use the separate repository.importHistoricalEntry path; the older service.save API is still present for compatibility and must not be treated as a new-record entry point. Stored codes use uppercase ASCII letters/digits/underscore/hyphen, at most 40 characters. Code and farm/kind identity are immutable after creation. Farm/kind/code and normalized farm/kind/name are unique. Revision comparison prevents overwriting a newer snapshot.

Crop and material masters require an active unit in the same farm. A referenced unit cannot be renamed; a unit used by active masters cannot be deactivated. Material units cannot be changed after creation: no automatic conversion of historical quantities or stocks is attempted. Master creation/update, resource projections and append-only repository audit writes share one transaction. Audit records have no update/delete repository API.

Machine/worker projections preserve existing resource IDs. Material projection preserves inventory stock, prices and supplier fields on rename. The legacy inventory module remains closed by the existing authenticated routing; A04 does not introduce a purchase, pricing or stock-adjustment workflow. Categories, task types and suppliers are maintained now; their downstream business modules are not opened by this patch.

A one-time adoption marker prevents startup from resurrecting renamed or inactive entries. Persisted pre-A04 resource IDs are retained. Missing/invalid legacy codes receive deterministic `OLD-...` codes; duplicate historical names receive disambiguating suffixes. This adopts persisted values only, not arbitrary future user input.

Crop records still retain historical type/unit name snapshots. Authenticated crop editors and subdivision use active catalog dropdowns; SQLite validates selections inside the business transaction. An unchanged historical type/unit pair can be retained while editing other crop attributes. New selections require active crop and unit masters. No bulk rewrite of old crop names or quantities occurs. A future ID migration must preserve these snapshots.

## Suggestions

Suggestions are pending requests, not master records. A manager creates/selects an active matching-kind master and resolves the request with a reason; rejection requires a reason. Approval of one's own suggestion is prohibited. Resolving an already resolved request is rejected. Entry save and request resolution are separate explicit actions, each with audit records. Approval may create a new master with an automatically allocated code inside the same transaction, or link to an existing active master. Self-approval is prohibited.

## Verification

New tests cover real SQLite uniqueness, stale revisions, transaction rollback on expired access, unit constraints, stable projections, one-time adoption, crop selection validation, request ownership and resolution, and backup/restore. Flutter widget tests cover admin creation, employee suggestions, dropdown selection and expired sessions. Run scoped analysis/tests and the complete Flutter suite on the project's supported Windows toolchain before device verification.

## Test-data reset boundary (not yet executed)

All existing AGRICO app business records are currently test data, but deleting them is a separate, explicitly scoped operation, not a side effect of catalog changes or migrations. Before a reset, identify the actual local database(s), relevant farm(s), dependent business tables and audit/sequence implications; export a restorable snapshot and verify it; then delete in dependency order inside a transaction and reinitialize only the approved test-data scope. Do not delete local backup archives, application source, schema migrations, identity/permission configuration, or unrelated module data. Do not reset catalog codes independently while dependent inventory, crop or work-resource records remain. GitHub changes do not directly delete the user's Windows/device SQLite data.

## Reset preflight checklist — shared catalog and linked test data

1. Identify the actual AGRICO installation and the two SQLite databases (`agrico.db`, `agrico_costs.db`); never assume that the GitHub checkout contains the device's live test rows. Record the farm scope and table counts before proposing deletion.
2. Produce an encrypted local backup including both databases and associated media; verify it with the existing snapshot inspection and `LocalRestorePreflight.validate` on disposable SQLite files. A logical SQLite snapshot alone does not include external media files or catalog sync-journal tables.
3. Inventory dependent rows before any catalog reset: `company_catalog_entries_v1` references its own unit IDs, `company_catalog_requests_v1` references entries, `inventory_items_v2` projects materials and is referenced by `inventory_movements_v2`, and `parcel_work_resources` projects machines/workers and is referenced by `parcel_work_assignments`. Crop and parcel records can also carry historical catalog name/unit snapshots. Inspect finance, production and spatial links rather than guessing they are independent.
4. Treat `company_catalog_audit_v1`, `company_catalog_sequences_v1`, `company_catalog_bootstrap_v1` and `company_catalog_sync_*` as stateful metadata, not disposable UI caches. Clearing entries without coordinating counters, bootstrap/adoption and sync journals can resurrect test records or create identity collisions. Resetting the local database without handling already-published catalog data can re-import the old records.
5. Build and test a dedicated preview/confirmation transaction for a precise farm and module set. The preview must enumerate rows per table and blocked dependencies. Delete dependent test business rows before master rows only after verifying that every affected row is in scope. A failure must roll back the entire operation. Afterward reinitialize counters and bootstrap state consistently and confirm first generated codes and clean projections.
6. Never clear backup archives, permission/identity configuration, migrations or unrelated farm data. No destructive reset has been run by this documentation change.

## End-to-end audit — 2026-10-18

**Canonical creation:** `CompanyCatalogScreen` uses `CompanyCatalogService.create` for new masters and revision-checked `save` for edits. Approval uses `resolve`, which allocates a code transactionally. `SqliteCompanyCatalog` enforces uniqueness, dependent units, immutable identity and audit writes.

**Warehouse integration:** `InventoryCatalogScreen` selects an existing shared material when the catalog is supplied. `SqliteInventoryRepository.register` verifies that the selected material and active unit exist in the shared catalog, and updates the projected inventory row rather than creating another identity. Warehouse inventory movements remain separate and must not be cleared during catalog cleanup.

**Work-resource integration:** `ParcelWorkService.register` now calls `CompanyCatalogService.create` when a shared catalog is configured, allocating MAY/NS codes rather than accepting manually entered codes. `WorkResourceCatalogScreen` hides the manual code input in that mode. The resource projection and audit share the catalog transaction. The service's optional no-catalog compatibility path still registers directly through the work repository; it is not an approved new-master workflow. Before declaring unification complete, ensure all production composition routes supply the shared catalog, and retire or isolate any legacy route that does not.

**Historical compatibility:** `importHistoricalEntry` remains an explicit migration operation. The older `CompanyCatalogService.save(expectedRevision: null, code: nonempty)` still accepts historical-style codes for existing compatibility callers; new UI must use `create`. Hardening this legacy API requires a coordinated migration of older tests and callers, not an unreviewed deletion.

**Verification gate:** Integration tests cover all nine prefixes, code uniqueness, rollback, legacy-code high/low watermarks, edit immutability, request approval and the shared work-resource projection. GitHub Actions full regression is required on the final commit. Passing CI does not by itself establish on-device acceptance or prove that all legacy entry points are unreachable.

**Acceptance status:** The shared-catalog core is implemented and covered by automated tests; the production routing/legacy entry-point closure and on-device walkthrough remain explicit acceptance checks. Preserve test data until application-wide signoff and a verified final reset.


## Warehouse V2 and production-cost boundary — 2026-10-18

**Verified implementation boundary:** `InventoryCatalogScreen._MovementDialog` submits an `InventoryMovement` containing only farm, item, kind, quantity and timestamp. `InventoryService.record` authorizes the movement; `SqliteInventoryRepository.record` atomically updates stock, assigns a monthly NHAP/XUAT number and inserts the warehouse movement in its SQLite transaction. The warehouse record has no field/season allocation, unit-price snapshot, or production-cost link.

**Separate cost writer:** `MaterialProductionCostSyncService.syncExport` requires a field and resolves a season; it upserts a production cost using source `material` and sourceId `transactionId`. This is a separate cost-database operation, not part of the inventory repository transaction. Do not claim that a V2 stock issue automatically posts production costs or that the two databases commit atomically.

**Required integration before production-cost acceptance:**
1. Define explicit destinations (field and season) and a stable movement ID for production issues. Distinguish ordinary warehouse issues/transfers from production consumption.
2. Capture the historical unit price and unit of measure at issue time, rather than reading mutable current item metadata for later cost calculations.
3. Design a durable outbox/reconciliation boundary between inventory and production-cost databases. Commit stock movement and outbox intent together, then idempotently post cost with the same source ID; retry safely after interruption.
4. Test insufficient-stock and duplicate-ID rollback (no cost intent), repeated delivery (one cost), delayed retry, changes in catalog price/unit, and partial failure between databases. Include farm/field/season authorization and restore/replay behavior.
5. Until these gates pass, keep V2 warehouse movements as inventory-only transactions and mark automatic material-cost posting as **not yet integrated**. Do not introduce a best-effort second write from the UI.

**Inventory reporting:** Warehouse date filters and stock opening/closing balances use Laos calendar days (UTC+7), including midnight boundaries; the workbook remains read-only. This report is a stock ledger view, not a production-cost valuation report.
