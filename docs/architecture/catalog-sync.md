# A05 — catalog synchronization protocol

## Durable journal

The durable journal, sender coordinator, Firebase transaction transport and server Rules are implemented. The application continues to use its offline catalog until receiving, reconciliation and lifecycle wiring are complete. This checkpoint does not enable cross-device synchronization.

Every user catalog save, suggestion and resolution commits its audit and outbox operation in the same SQLite transaction. Adoption of persisted pre-A04 values does not enqueue a mutation under the migration actor: initial publication will require explicit catalog-management authority and reconciliation with the server.

The protocol tables are `company_catalog_sync_outbox_v1`, `company_catalog_sync_shadow_v1`, and `company_catalog_sync_device_v1`. Every operation has an immutable random ID, actor, farm, entity, target, payload, reason, and base/new cloud version. Cloud versions are independent of A04's local revision. Multiple offline edits form a chain. A pending, rejected or conflicted earlier operation blocks later operations for that target, including operations made by a different user on a shared phone.

The sender may select only its own operations, in the current farm, while the verified session and cloud-sync permission remain valid. A staff actor may send a pending suggestion with catalog-request permission, but cannot publish a master or approve a request without catalog-management permission. Permission scope overrides, including explicit empty scopes, remain effective. Restored devices cannot select sends until authoritative reconciliation.

A network failure leaves the exact operation pending; it must not generate another ID. An authoritative acknowledgement must match both the operation's cloud version and canonical payload. Acknowledgement and cloud shadow commit atomically. Replaying the same acknowledgement is harmless; mismatched receipts do not advance the shadow. Conflict/permission failure is retained, not discarded or force-overwritten. No automatic overwrite or account impersonation is introduced.

Protocol tables are excluded from backups. Activation clears device protocol tables and blocks sending for restored farms in the same restore transaction. This prevents a backup from resurrecting pending sends, receipts or stale cloud baselines. Business entries, suggestions and local audit records remain backed up. Existing A04 backup compatibility is retained.

## Remaining checkpoints

1. Receiver/conflicts: stage and validate server data, apply projections atomically, never replace a dirty local entry without resolution, retain business IDs and historical snapshots. Reconcile restore before enabling sends; preserve revoked actors' unsent operations for controlled recovery, never resend them as another account.
2. UI/lifecycle: pending/conflict/error counts, last successful sync, retry and resolution actions; synchronization when opening/resuming and during connectivity recovery; stop on sign-out. A synchronization attempt must not claim success from the Firestore cache.
3. Device verification: staff suggestion on phone A, manager review on phone B, offline retries/restarts, simultaneous edits, deactivation propagation, revocation, and restore isolation.

## Validation

The checkpoint adds real SQLite tests for actor/farm separation, expired or denied sessions, staff versus manager selection, atomic rollback, ordered cloud versions, idempotent acknowledgements, invalid receipts, conflict barriers and restore blocking. Existing catalog and backup tests must also pass, followed by the full suite. No Firebase deployment or APK installation is necessary for this source checkpoint.

## Sender coordinator checkpoint

`CatalogSyncSender` drains actor-owned commands in cloud-version order, with a bounded operation budget and one shared in-flight Future for concurrent calls. It checks the session, authenticated UID and current local permissions before each send. Disposal or a session change during a server request leaves the operation pending for its original actor to reconcile later. Definitive server denials and conflicts remain durable barriers; uncertain network outcomes and unexpected failures preserve the pending command.

The transport contract requires atomic compare-and-swap with an immutable receipt and complete-command verification on retry. Receipts must match operation, actor, farm, entity, target, version and canonical payload before SQLite acknowledgement. Changing an object obtained from the command payload cannot mutate the stored command.

Fifteen real-SQLite coordinator tests cover ordered sends, outages, lost responses after a remote commit, conflict barriers, definitive denials, SDK/session mismatches, forged receipts, concurrent calls, permission loss, disposal, unexpected failures, operation budgets and restore isolation. The test transport models the protocol; it is not a Firebase emulator or a production gateway.

## Firebase transport and Rules checkpoint

`FirebaseCatalogSyncTransport` uses a server transaction to commit the target, immutable operation receipt, uniqueness locks and unit-reference counters atomically. The authenticated Firebase UID must match the command actor. A retry reads the same operation receipt and verifies the complete original command before acknowledging it, even if the target has advanced. Uncertain errors retain the original operation ID; server denials and version conflicts remain durable barriers.

Rules preserve the A03 account policy and validate current membership, lease, scoped catalog authority, immutable codes/material units, code/name uniqueness, active dependencies, unit references and suggestion ownership/approval. Hash lock IDs use uppercase UTF-8 SHA-256. Canonical name validation supports the app's English, Vietnamese and Lao profile. Other alphabets with case-changing letters can fail closed; extending that profile requires matching client and Emulator tests.

Thirty-eight actual Firestore Emulator tests cover A03 regression and adversarial catalog writes, concurrent duplicate creation, auxiliary-write omission, forged counters/receipts, name normalization and maximum role/dependency paths. Six additional Dart tests validate receipt identity and key encoding. Flutter analysis and the full suite must pass on the supported Windows toolchain before advancing. See `docs/security/catalog-sync-setup.md`.

Initial publication of adopted A04 entries still requires an explicit manager action, authoritative reconciliation and dependency ordering. Receiving, conflict resolution, restored-device reconciliation and app wiring remain pending.

## Receiver staging checkpoint

`FirebaseCatalogReceiveTransport` queries bounded pages with `Source.server`, ordered by document ID. Staff request queries filter `payload.actor_uid`; managers may read all requests in their farm. Cache snapshots and pending local Firestore writes cannot certify received data. Authentication and project identity are checked around network reads.

`CatalogSyncReceiver` shares concurrent calls, checks current permissions/session around every page, validates IDs, payload schemas, canonical names and timestamps, and stages a page atomically into `company_catalog_sync_inbox_v1`. Inbox rows are separated by reader and farm. Same-version content changes are rejected; older pages cannot regress staging. Pagination follows UTF-8 document ID ordering. A bounded run reports incomplete instead of claiming complete synchronization. Retrying starts at the beginning and is idempotent; pages are not a globally consistent snapshot and absence never means deletion.

Staging does not alter business tables, shadow baselines or outbox acknowledgements. Dirty barriers are computed from all unresolved operations, including another actor's edits. Inbox data is excluded from backups and cleared by restore; receiving never clears restore blocking. Inbox reads are internal protocol operations and are not wired to UI.

Eighteen receiver tests cover real SQLite atomic staging, replay/regression, dirty actor separation, privacy, authorization revocation, sign-out/disposal during reads, network errors, pagination limits/order, malformed records and restore blocking. A standalone Dart/SQLite harness can exercise this logic; supported Flutter analysis and the full suite remain required on Windows.

Projection, dependency reconciliation, conflict decisions, authoritative restore recovery, explicit initial publication and app lifecycle/UI wiring remain subsequent checkpoints. This source patch does not enable device synchronization or require Rules publication.

## Clean projection and conflict recording checkpoint

`CatalogSyncProjection` applies reader-owned staging using a fresh verified session and current catalog visibility. Active units precede dependent entries; retired units follow consumers; requests follow masters. Each item commits its business projection, receive audit, cloud shadow and conflict cleanup atomically. Receive audits record the local reader and exact before/after business snapshots; they do not attribute the operation to that reader or enqueue another cloud mutation. Local revisions increment independently of remote revisions/cloud versions. Existing machine/workforce and inventory projections are reused; inventory stock and price are preserved.

Unresolved sends by any actor, unpublished local rows, local changes against the known shadow, duplicate code/name, changed immutable identities, missing dependencies and unit references become durable reader/farm-scoped conflicts. A failed item cannot advance its shadow or partially modify business data. Another farm's colliding ID is never exposed in the local conflict snapshot. Reapplying the same version is idempotent; received data never acknowledges an outgoing operation or clears the restore barrier. Conflicts are excluded from backup and cleared on restore together with the other protocol tables.

Previously approved requests may reference a subsequently retired master: projection preserves that historical reference. A current active crop/material still requires an active unit. Receiving pages and applying items are not a globally consistent farm snapshot; missing records do not imply deletion. Bounded runs report whether all selected records were visited, separately from conflict counts. A caller must raise the bounded budget or provide later lifecycle scheduling for larger catalogs.

Twenty new real-SQLite tests cover atomic clean projection, independent revisions, replay, dependency ordering/retry, dirty and unpublished local data, forged same-version staging, uniqueness rollback, unit/material invariants, inventory balances, cross-farm privacy, legacy resource collisions, authorization rollback, restore isolation and historical request references. Windows Flutter analysis and the complete test suite remain required.

This checkpoint detects and retains conflicts. Explicit choices to accept remote data or preserve/rebase local edits, initial publication, full restore reconciliation and application wiring remain subsequent checkpoints. No local history or queued operation is discarded automatically. No Rules deployment or APK installation is needed for this source patch.

## Guarded conflict decisions checkpoint

`CatalogConflictDecisions` provides manager-only choices with a mandatory reason and an immutable review snapshot. `FirebaseCatalogConflictVerifier` re-reads the exact target with `Source.server`, rejects cache/pending writes, validates project and UID identity, and limits network waiting to twenty seconds. A changed server version, operation or payload invalidates the review. The SQLite transaction also checks current staging, the conflict snapshot, local data, shadow progression and current authority before committing.

`acceptRemote` applies the reviewed server record through the same business guards, advances the shadow and records before/after plus reviewed remote metadata in durable business audit. `keepLocal` applies only to master entries: it preserves the reviewed local content, advances the known remote baseline and creates one new actor-owned immutable command with that baseline version. Neither choice bypasses immutable codes/material units, unit references, uniqueness or dependency checks. Old review reuse, concurrent choices and permissions lost during a request cannot authorize another write.

Any unresolved pending, blocked or conflicted outbox operation for the target blocks both choices. Receipt recovery must settle those operations first; this checkpoint does not cancel them, relabel their actor or discard their history. Keeping a pending suggestion cannot reopen an approved remote request; managers can accept its remote result. Full receipt recovery, initial publication, restore reconciliation and application/UI wiring remain subsequent checkpoints. Restore sending remains blocked even after a decision.

The reviewed remote/local snapshots and choice are stored as `conflict.review` audit, alongside the actual business before/after audit. These are business history and therefore remain backed up. Temporary conflicts remain device protocol data. Ordinary offline edits against an unchanged cloud baseline no longer generate a new conflict during projection; a genuinely newer/different server baseline still does.

Eighteen decision tests and one projection regression cover real SQLite guarded choices, rebase intent, stale server/local reviews, queue preservation, role/lease/SDK changes, network errors, concurrent requests, authorization rollback, uniqueness/references, farm privacy, request approval history and restore blocking. Supported Windows Flutter analysis and the full suite remain required. No Rules deployment, APK installation or app wiring is performed in this source checkpoint.


## A05 — authoritative receipt recovery

- `CatalogReceiptRecovery` reads existing immutable operation receipts with the original actor and farm. It never sends, cancels, reassigns or recreates an operation. Overlapping calls share one run; each run is bounded.
- The Firebase lookup uses `Source.server`, rejects cached/pending-write snapshots and requires a committed `acceptedAt` timestamp. All ten immutable command fields are compared, including base/new versions, complete payload, reason and occurrence time.
- An absent receipt is only a point-in-time observation: pending, blocked or conflicted operations remain unchanged. Network uncertainty also retains the exact command. The sender may later retry the same ID. There is no force-cancel path.
- An exact receipt can acknowledge pending or rejected commands only in dependency order and against the expected shadow baseline. Recovery checks the current SDK actor, membership, farm, lease and scoped permissions before/after reads and inside the acknowledgement transaction. Shadow advancement or an earlier unresolved command fails closed.
- Recovery changes protocol acknowledgement/shadow only; business rows, business audits, staged downloads and recorded conflicts remain intact. The normal sender acknowledgement contract is unchanged. Restore isolation remains blocked.
- This checkpoint has no app/UI wiring, Rules changes or deployment. Absence/rejection reconciliation, initial publication and restore reconciliation remain separate work.


## A05 — reviewed initial master publication preparation

- Existing adopted catalog masters have no implicit send authority. `CatalogInitialPublication.review` captures one manager-selected business row; `prepare` requires a reason and a fresh server-only target read. It only queues a version-0-to-1 command and writes a local `sync.prepareInitial` audit. Business identities, codes, revisions, quantities and historical records remain unchanged.
- Any existing target on the server, including an equal payload, requires receive/reconciliation instead of initial publication. Any local outbox history, shadow, staged target or recorded conflict also blocks preparation. Repeating the action cannot create duplicate commands.
- Absence is advisory, not a reservation. The existing sender transaction still enforces version CAS, typed name/code uniqueness, current authorization, unit references and immutable server receipts. A concurrent server creation is rejected rather than overwritten.
- Units must be prepared first. A dependent entry requires either an active unit with an exact fresh remote shadow and matching local business fields, or one same-actor pending initial unit command with an unchanged payload and no shadow. Blocked, conflicted, foreign-actor, changed or retired units do not authorize dependencies. Multi-command unit chains require reconciliation before this action.
- Server reads reject cache/pending-write metadata. SDK UID, membership, farm, permissions and lease are rechecked around reads and within the SQLite transaction. A changed reviewed row, restore barrier, logout or revocation prevents preparation; late revocation rolls back both command and audit.
- This checkpoint handles one reviewed master per call. Suggestions, batch UI, initial publication scheduling and restore reconciliation remain separate. It does not wire app routes, send commands, deploy Rules or clear restore isolation.
