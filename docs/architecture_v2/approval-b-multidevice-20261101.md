# Approval B authenticated multi-device catalog

Checkpoint base: 790101a88181df65aa6e979ee07406706f10218d. Local/Emulator implementation; no production authority provisioning or business permission changes.

## Contract and scope

companyApprovalAuthority accepts listDrafts/getDraft/getActive with farm, kind, currency (getDraft also digest). Membership identity/farm, live membership lease, explicit allFarm capability and separately provisioned managerUids/activatorUids are checked in one Firestore transaction. Policy managers may read with approval.policy.manage; authorship still requires approval.policy.manage plus approval.limits.manage. Activators require approval.policy.activate. A technical admin, financial reviewer or cross-farm user cannot read the catalog implicitly. Existing farm is the tenant boundary; no invented company identity mapping.

Catalog is bounded to one kind/currency and its latest pending draft head, not an unbounded history query. getDraft only serves that pending head; an active or superseded draft is not returned by getDraft. The same response includes active metadata and expectedActive identity, avoiding multiple inconsistent snapshots. No new Firestore indexes are required. Direct client authority/policy collection read/write remain denied by existing Rules.

Envelope: canonical policy, digest, version, proposedBy, proposedAt, authorityRevision; active also activatedBy/activatedAt/reference. Revoked authors/activators or old grant revisions withhold unusable payloads; raw current identity remains for CAS replacement by a newly authorized manager. Malformed canonical records fail closed.

## Mutation, replay and audit

Activation requires expectedActive {version,digest} or null, expectedDraftHead {version,digest}, expectedAuthorityRevision. All reads precede writes in one server transaction. The selected draft must still be head, author and independent activator current, and version newer than active. A retry of the same activation actor/digest/original CAS before-image returns the original reference without another activation write; a newer head or a different winning actor rejects the replay. Version/history/activation audit are atomic. Propose and catalog reads have server audit entries; retries of an existing proposal do not create another proposal effect.

After an unknown activation response, Flutter can recover the already-current same-actor proof while the head still matches; this completes local metadata without another mutation. Offline/denied responses never authorize posting. Verify remains live before/after native posting; unchanged business floors, self kinds/caps, conflict/exposure checks and PeriodLock still apply.

## Client import and UI

Authenticated catalog envelopes are checked for exact payload keys, canonical digest, author identity, scope, head/version, revision and active identity. Import is transactional, preserves server author/time on a new device, rejects same-version/different-payload conflicts and cannot resurrect superseded local state. Existing local author's creation time remains immutable when its own row becomes active; server proposal time/revision are recorded in import audit reason. Audit after_json always equals the persisted row; no relaxed hash-chain validation. No SQLite schema or migration changes.

Remote active snapshots are verified online; local configuration is metadata, never an authority cache. list reauthorizes through the server for the real catalog adapter. A selected-policy sync imports one bounded catalog; it does not silently overwrite local drafts. No automatic polling or cross-currency merge is added. Sensitive reads create audit writes; operation counts/production billing have not been measured here.

The existing policy panel adds explicit kind/currency sync (VI/EN/LA). Scope/user/store/read-access changes clear rows/messages, invalidate delayed responses and dismiss policy dialogs. Requests bind UID and session epoch; native Firebase auth-state changes are observed per request so same-UID logout/login cannot reuse an old response. Existing HTTP client injection supports an explicit sessionEpoch for tests/alternate hosts. No stream subscription is retained for the service lifetime.

Revocation is enforced at each server interaction and before/after posting. No new push invalidation channel is introduced: already displayed metadata can persist until client membership notification or the next denied interaction. This is not a claim of instantaneous invalidation on an unobservable server-only change. Android/native account/lifecycle testing remains a separate gate.

## Compatibility and rollout

New server activation requires CAS. Old clients without it fail closed; server-only rollout would prevent those clients from activating policy. Coordinate server/client versions, review required Functions exports/configuration and production authority separately. Old records missing server proposal metadata are not fabricated or backfilled. Owner must decide re-proposal/review if such development records are encountered. No production data migration or destructive cleanup.

Policy, business role floors, UID/cap values, grant provisioning, signing/configuration and Android native E2E still need owner acceptance. Emulator fixtures are synthetic and do not certify IAM, App Check, production data, native E2E or offline multi-device business synchronization.

## GitHub FULL checkpoint

cleanup/erp-v2-full-20261101 was absent during preflight. No ref was created or pushed. With a separately approved push of that ref pointing at 790101a..., current workflow conditions select FULL and skip FAST/release. That run would certify only the old checkpoint, not this uncommitted multi-device package. New code requires its own approved commits/SHA and FULL verification afterwards. No main/workflow changes in this package.
