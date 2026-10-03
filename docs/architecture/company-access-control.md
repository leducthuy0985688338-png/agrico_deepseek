# Company access control — A01/A02

Status: A01 policy foundation is now connected to the A02 real Firebase login/session gate. Firebase account provisioning and rules publishing are still operational setup steps, not performed by the patch. No business-data migration or deletion.

## Approved templates

| Role | Default business scope | Responsibility |
|---|---|---|
| systemAdmin | Farm | Accounts, roles, catalogs; no automatic business approval |
| director | Farm | Reports and business approvals |
| operationsManager | Project | Plans, tasks, resources, acceptance |
| departmentManager | Department | Department work and verification |
| teamLeader | Team | Assignments, acceptance, attendance |
| agronomist | Assigned fields/tasks and own | Crops and technical work |
| gisOfficer | Project | Geometry, surveying; separate boundary verification |
| machineOperator | Assigned tasks/machines/fields and own | Completion submissions, machine logs |
| fieldWorker | Assigned tasks and own | Work submissions and attendance |
| equipmentCoordinator | Assigned machines and team | Allocation, maintenance, verification |
| warehouseKeeper | Assigned warehouses | Receipts, issues, counts; no default adjustment |
| purchasingOfficer | Department | Requests and purchasing drafts |
| accountant | Department | Finance preparation/posting/corrections; no default approval or payroll |
| cashier | Department | Payment recording; approved-document validation belongs in workflow |
| hrOfficer | Department | Employee and attendance administration; payroll separately granted |
| officeStaff | Assigned tasks and own | Office work and requests |
| auditor | Project | Read and review; no business mutation |

The exact permission sets live in company_roles.dart and are tested against PermissionCodes.values. Templates are AGRICO design decisions, informed by public Farmbrite role documentation and Microsoft Dynamics role-based security; they are not a mandatory industry standard.

## Policy rules

- Stable permission codes remain backward compatible. New scope IDs must be populated from trusted membership/resource records.
- Role assignments combine by permission, with separate scopes per permission. Admin catalog access cannot broaden operator task access. Explicit deny overrides grants and roles.
- Catalog editing defaults to systemAdmin. Delegated grants require an explicit scope; ordinary employees request additions and choose approved entries.
- ApprovalPolicy rejects the document author and requires a supported approval permission. Workflow services must load the real author from storage; UI-supplied authors are not trustworthy.
- Empty scope denies access. Inactive membership, wrong farm, and an expired offline authorization deadline deny access. The deadline is an optional primitive, not a configured production lease.
- Profiles copy collections into immutable snapshots. These snapshots do not authenticate users or prove that cached permissions are server-issued.
- Legacy AuthorizationSubject callers keep their previous scope behavior. Business services still need migration to scoped queries and per-operation guards.

## Remaining implementation

A02: real authentication, individual memberships, admin account/role management, trusted cached membership and configurable offline validity. Backend rules must validate identity and farm membership independently of client code. Initial enrollment requires connectivity. Revocation on disconnected devices can only take effect when learned or when the offline lease expires.

A03: shared catalogs/units with IDs, restricted create/edit/archive at service and backend, replace free-text choices, preserve historical references. Implement proposal workflow separately.

A04: durable outbox, scoped downloads, server-side revalidation of permissions and versions, visible conflict resolution, immutable approved-document history. cloud.sync permission alone does not grant access to all synchronized data.

No phase may erase the current saved parcels/crops. No client role template by itself constitutes an authorization boundary.

References:
- https://help.farmbrite.com/help/how-can-i-create-a-user-with-limited-access-to-my-farmbrite-account
- https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/role-based-security

## A02 rollout

See [Firebase account setup](../security/firebase-account-setup.md). Demo login and automatic full-access subjects are removed. Server-read memberships bind cached sessions to Firebase UID/project and the existing local-farm. Offline access has an administrator-issued deadline; expired, revoked or mismatched sessions fail closed. Unsupported legacy routes remain closed while per-operation scoped service guards and shared catalogs are implemented. Individual account/role management through an in-app Admin screen and business-data sync/outbox remain pending.

## A03 — Account access administration

Account access is managed online with farm-scoped Firestore transactions, expected revisions and mandatory append-only before/after audits. The client cannot edit its own grant, any registered root administrator, the server administrator registry, or the offline policy. The server checks active authority and membership, farm, expiry and explicit permission denials on every change. Up to four role assignments can be saved per membership; scopes remain per role/per permission.

An active user can renew only its unchanged grant's offline deadline when enabled by a Console-managed company policy; the server validates the requested deadline against `request.time`. A disconnected device keeps the previously verified expiry and never renews locally. Locking AGRICO access does not disable Firebase Auth or delete SQLite business data. Authentication user creation remains in Console for the Spark-compatible checkpoint. See `docs/security/company-account-admin-setup.md` for bootstrap, policy, index, verification and deferred module scope.
