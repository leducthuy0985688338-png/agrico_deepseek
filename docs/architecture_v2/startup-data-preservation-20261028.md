# Startup data preservation — 2026-10-28

## Contract

Missing historical test-cutover state is not permission to delete installed
business data. AgricoV2Root calls ProductionV2TestCleanup.validateStartup after
opening the primary DB and before V2 module schema/bootstrap work. It does not
open the legacy costs DB for reset and never calls the destructive helper.
Ordinary additive schema upgrades and catalog/sequence reconciliation remain.
No table schema, business identity, receipt, Rules or Functions protocol changes.

The startup guard is read-only (including no marker CREATE/UPDATE):

- No marker table: preserve all rows and proceed.
- An existing empty table: inspect its schema first; only the recognized
  four-column historical shape proceeds, without any schema or data writes.
  Columns are id INTEGER PRIMARY KEY, phase TEXT, counts_json TEXT and
  completed_at TEXT. Unknown columns/types/key shapes fail closed.
- One valid complete marker: preserve all rows and proceed; no reset/rewrite.
- main_done: stop bootstrap with an explicit recovery error, preserving both
  remaining databases. Never resume deletion or mark a partial reset complete.
- Unknown/malformed marker: fail closed without data or marker writes.

A missing marker with existing V2 data no longer invokes or requires a reset.
This does not make old and new ledgers interchangeable or migrate their meaning.
Legacy rows remain stored; V2 production continues to use native parcel IDs,
seasons/plans and material/labor/machine projections. Compatibility/backup paths
still need old schemas. No adapter or legacy decoder is removed.

## Historical explicit helper

ProductionV2TestCleanup.run is retained for synthetic regression fixtures and
requires confirmedDisposableTestData. False is rejected before schema/data
writes. No shipped application caller passes confirmation; only tests do so.
A boolean is an explicit caller confirmation, not a detector of test data, a
user recovery UI, or authorization to reset a device in production. Do not add
an application call to this helper. The former tests still assert its original
transaction rollback and cross-file retry behavior on disposable fixtures.

## Recovery and restore boundary

The original primary deletion transaction could have committed before a cost
DB failure (main_done). This change cannot recover already deleted records.
Stop and preserve both files and any pre-cutover backup; recovery/eligibility
requires an explicit operator decision. No marker repair or automatic import
is performed by this change.

Local backup preflight, integrity checks, device-queue quarantine, period
triggers and confirmed restore activation remain unchanged. Markerless legacy
backup roundtrip is covered with synthetic two-file linked data. Existing
post-cutover restrictions still reject incompatible legacy backups; they are
not weakened to force recovery. A historical interrupted reset may therefore
need a separately reviewed recovery procedure rather than the current UI.

## Verification

Regression fixtures use in-memory and freshly-created temporary SQLite files,
never application documents or production data. Guard tests compare both DB
snapshots and schema, run the primary under PRAGMA query_only, and check links,
stock and document sequences. File reopen tests model repeated startup after
an interruption; they are not a physical power-loss or native-device test.

Scope also includes fresh install, absent/empty/complete/malformed markers,
V2-without-marker, malformed-empty/valid-empty marker schema, unconfirmed reset
rejection, markerless legacy backup/apply,
and a wiring regression preventing destructive reset in the composition.
See the Downloads W0/W1 acceptance package for exact logs, SHA and limitations.
