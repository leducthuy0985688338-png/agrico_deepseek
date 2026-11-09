# Native V2 production cutover — 2026-10-25

> Historical authorization for a specific disposable test dataset, not a general
> startup policy. The automatic reset described below is superseded by
> [Startup data preservation — 2026-10-28](startup-data-preservation-20261028.md).
> Current startup only inspects historical markers and never resumes deletion.

The user explicitly confirmed that all installed business data is test data and
requested removal of incompatible legacy data. This supersedes the earlier
plan to preserve test data and map legacy fields to V2 parcels.

## Authoritative model

- Land identity: `land_parcels.id`, scoped by `farm_id`. Only active `fieldPlot`
  parcels can receive new production seasons and material issues.
- Seasons: `production_seasons_v2`, referencing the V2 parcel directly. The
  parcel/farm identity is immutable; seasons can be closed/reopened. Names are
  unique per farm/parcel. `starts_on` is a validated Laos calendar date.
- Material costs: `production_material_costs_v2`, keyed by the unique warehouse
  movement ID. Item name, unit, quantity, unit price and amount are snapshots.
- A production issue validates parcel/season/farm/date, subtracts stock, allocates
  the XUAT code, inserts the movement and inserts its material cost in one
  SQLite transaction in `agrico.db`. Any failure rolls back all of these writes.
  Ordinary warehouse issues do not create production costs.
- No V2 writer uses `fields`, `production_seasons`, `production_costs`, a
  field-link bridge or a cross-database outbox. The old bridge dialog and V2
  reconciler are removed. No user is asked to recreate a legacy field.
- Season creation/closure requires farm-wide `production.plan`; stock issues
  require `inventory.manage`; material cost viewing requires `finance.view`.
  The workspace is available from Seasons, Warehouse and parcel cost details.
- Material consumption costs remain distinct from financial expense documents.
  They are not summed together because purchases and consumption can represent
  the same expenditure. Inventory prices currently have no currency field;
  the UI does not invent a currency or a cross-currency grand total.

## One-time authorized test-data cleanup

Bootstrap initializes the new tables and awaits `ProductionV2TestCleanup`.
It removes legacy field links, cost intents, production logs, seasons, field
measurement history and fields. It clears old local-farm inventory movements,
sets inventory stock to zero and clears only the NHAP/XUAT sequence scopes.
It also clears legacy `production_costs` rows in `agrico_costs.db`.

V2 parcels/geometry, survey data, shared catalog identities, price/supplier
configuration, finance documents, tasks, identity/session settings, backup
archives and external media are not removed. No cloud data is deleted.

The primary cleanup is transactional. A durable `main_done` marker is committed
with it. The legacy cost clear is idempotent and retried after interruption;
only then is the marker marked `complete`. The new UI is not exposed while
bootstrap is incomplete. A completed cutover never clears newly entered stock
on subsequent launches. An unexpected multi-farm inventory or native production
rows without a marker stops cleanup rather than erasing them.

Restore preflight validates native season/cost identities and movement values.
Once cutover exists, backups containing incompatible legacy production rows or
legacy cost records are rejected, preventing resurrection of the removed data.
A backup with native production rows but no cutover marker is also rejected.

## Verification boundary

The headless verification driver executes the actual repository, service,
backup preflight and cleanup classes through sqflite_common's native FFI API;
it does not use Flutter platform channels or widgets. It checks atomic failure,
replay, historical pricing, scope/date guards, backup integrity, primary cleanup
rollback, cross-file interruption and one-time cleanup. Static analysis uses
real public package sources and SDK stubs. These checks do not replace the
Windows Flutter regression suite, Android build or installed-device acceptance.

The delivery script backs up the existing review source, replaces only the
listed implementation/test files, removes the obsolete bridge/reconciler,
runs scoped tests, analyzer and the full suite, then optionally builds/installs
and opens the debug APK. Device data cleanup happens when the installed app
reaches its authenticated V2 bootstrap, not when source files are copied.
