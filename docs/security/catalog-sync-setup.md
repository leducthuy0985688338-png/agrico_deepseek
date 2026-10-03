# Catalog sync source checkpoint

Do not publish Rules or install a new APK for this checkpoint. The transport is not yet wired into the application. Existing account administration and offline catalog behavior remain in place.

## Server protocol

All catalog protocol documents are under `agrico_catalog/{farmId}`:

| Collection | Purpose |
| --- | --- |
| `entries/{id}` | Master payload, cloud version and operation ID |
| `requests/{id}` | Owned suggestion payload and cloud version |
| `operations/{id}` | Immutable complete-command receipt, previous payload and server acceptance time |
| `keys/{kind}~{type}~{hash}` | Code/name ownership; uppercase SHA-256 of UTF-8 value |
| `unit_usage/{id}` | Total and active entry references to a unit |

A transaction reads an existing receipt first. An exact retry returns that receipt; a different command under the same ID is rejected. Otherwise it checks the base version and writes the target, receipt and required auxiliary documents together. `acceptedAt` is a server timestamp. The client command timestamp is audit metadata, not authorization time. Network uncertainty retains the original pending operation.

Rules enforce lease validity and scoped authority at server request time. Codes cannot change. Material units cannot change. Referenced units cannot be renamed; active references prevent unit retirement. Name/code locks persist for retired entries. Staff may submit and read their own pending suggestions; managers resolve them with an active entry of the correct kind and cannot approve their own suggestion. No hard deletion is enabled.

The A03 account Rules are retained. Additional catalog helpers and matches precede the default deny. Name-key validation supports English, Vietnamese and Lao. Other case-changing alphabets require an explicit profile extension and tests; unsupported normalization fails closed.

## Validation

Run Flutter analysis, the transport tests, catalog/backup/permission tests and the full suite through the supplied guarded PowerShell patch. Run `npm --prefix tools/access_rules test` for the actual Emulator suite. It uses only `demo-agrico-access`; no Firebase login or production deployment is required. The pinned dependencies and Java runtime are needed, and the first Emulator run can require a download.

The Emulator suite contains 38 tests, including the existing account tests and adversarial catalog tests. Receiving, conflict resolution, initial publication, restore reconciliation and lifecycle/UI integration must be implemented before device synchronization is enabled.

References: [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions), [Rules hashing](https://firebase.google.com/docs/reference/rules/rules.hashing).
