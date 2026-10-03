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
