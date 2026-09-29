# AGRICO contributor instructions

## Scope and checkpoint

- Work in a focused branch based on the agreed `architecture/v2-foundation` checkpoint. Check `git status --short`, branch, local HEAD, and remote ref before edits. Stop and report unexpected changes or divergence; never reset, rebase, stash, or overwrite them to satisfy a task.
- Keep infrastructure, domain changes, and migrations in separate changes. Do not commit, push, open a PR, or merge when the task explicitly prohibits them.
- Read actual source and tests before editing. Treat checkpoint reports as context; source determines current behavior. Make the smallest change that satisfies the approved contract.

## Locked architecture

- UI → Application → Domain → Repository interface → SQLite repository → SQLite. Offline-first and WGS84 / EPSG:4326 remain mandatory.
- Business identity, stable `SpatialFeature.id`, and revision identity are distinct. Spatial revisions are append-only; spatial creation and updates are atomic.
- Once a LandParcel spatial identity is established, `spatialFeatureId` cannot change to another ID. Spatial writes require a persisted link, matching non-null parcel identity, an existing linked feature, and LandParcel feature type. Preserve Sprint 12 guards.
- `ownerHouseholdId` references Household business identity; `ownerDisplayName` is a display snapshot. `LandUseProfile` is separate. Metadata-only edits create no spatial revision; omitted/null metadata means no change. Preserve Sprint 11 behavior.
- Sprint 13 audit classified geometry ownership as ambiguous. Sprint 13A authorizes only `SpatialFeature.geometry` ↔ resulting `SpatialFeatureRevision.geometry` pair integrity. Do not assume that SpatialFeatureRevision is the final canonical LandParcel authority or alter LandParcel geometry, GPS/KML, schema, or reads without a later decision.
- Preserve Vietnamese, English, Lao UI localization and original Unicode user data.

## Verification and review

- For a micro-change, run relevant targeted `flutter test test/...`, then `git diff --check`. CI FAST runs focused architecture tests and analyzer. CI FULL runs the full suite and analyzer before a checkpoint; Android build is a separate release gate.
- Analyzer currently has existing warnings/infos; CI uses `--no-fatal-infos --no-fatal-warnings`. Do not introduce new analyzer errors or unrelated warnings.
- Review the diff against the approved scope and tests before checkpoint. Stop if a fixture reveals a legitimate conflicting contract; report evidence instead of changing the contract silently.
