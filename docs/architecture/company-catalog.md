# Company catalog — A04

## Scope

The authenticated Settings route provides units, crops, machines, workers, materials, task types, suppliers, income categories and expense categories. This is a local SQLite checkpoint. Cross-device transport, server authorization for catalog mutations and conflict reconciliation are deferred. Firebase Rules remain unchanged. The UI states this limitation.

## Rights

- `catalog.view`: read the farm's masters.
- `catalog.manage`: create/edit masters and resolve suggestions.
- `catalog.request`: submit suggestions and read one's own suggestions.
- Explicit denied permissions take precedence. Sessions are checked again within writes, including before transaction commit. No farm crossing is permitted.
- Field editing, work entry and inventory movement permissions alone do not permit master registration. The legacy reconciliation import requires catalog management.

## Persistence and invariants

`company_catalog_entries_v1`, `company_catalog_requests_v1`, `company_catalog_audit_v1` and `company_catalog_bootstrap_v1` form one optional backup group. Partial groups are rejected. Restoring a pre-A04 backup clears live catalog tables, allowing the restored business snapshots to be adopted subsequently.

Codes use uppercase ASCII letters/digits/underscore/hyphen, at most 40 characters. The UI normalizes new codes to uppercase. Code and farm/kind identity are immutable after creation. Farm/kind/code and normalized farm/kind/name are unique. Revision comparison prevents overwriting a newer snapshot.

Crop and material masters require an active unit in the same farm. A referenced unit cannot be renamed; a unit used by active masters cannot be deactivated. Material units cannot be changed after creation: no automatic conversion of historical quantities or stocks is attempted. Master creation/update, resource projections and append-only repository audit writes share one transaction. Audit records have no update/delete repository API.

Machine/worker projections preserve existing resource IDs. Material projection preserves inventory stock, prices and supplier fields on rename. The legacy inventory module remains closed by the existing authenticated routing; A04 does not introduce a purchase, pricing or stock-adjustment workflow. Categories, task types and suppliers are maintained now; their downstream business modules are not opened by this patch.

A one-time adoption marker prevents startup from resurrecting renamed or inactive entries. Persisted pre-A04 resource IDs are retained. Missing/invalid legacy codes receive deterministic `OLD-...` codes; duplicate historical names receive disambiguating suffixes. This adopts persisted values only, not arbitrary future user input.

Crop records still retain historical type/unit name snapshots. Authenticated crop editors and subdivision use active catalog dropdowns; SQLite validates selections inside the business transaction. An unchanged historical type/unit pair can be retained while editing other crop attributes. New selections require active crop and unit masters. No bulk rewrite of old crop names or quantities occurs. A future ID migration must preserve these snapshots.

## Suggestions

Suggestions are pending requests, not master records. A manager creates/selects an active matching-kind master and resolves the request with a reason; rejection requires a reason. Approval of one's own suggestion is prohibited. Resolving an already resolved request is rejected. Entry save and request resolution are separate explicit actions, each with audit records; resolution never silently creates a master.

## Verification

New tests cover real SQLite uniqueness, stale revisions, transaction rollback on expired access, unit constraints, stable projections, one-time adoption, crop selection validation, request ownership and resolution, and backup/restore. Flutter widget tests cover admin creation, employee suggestions, dropdown selection and expired sessions. Run scoped analysis/tests and the complete Flutter suite on the project's supported Windows toolchain before device verification.
