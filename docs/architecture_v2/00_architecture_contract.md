# AGRICO Architecture v2 — Architecture Contract

Status: APPROVED
Baseline: main @ 930057facf7a3fb2b8bfcfe4554170e3fab8c0cd

## Non-negotiable principles

1. Feature-first architecture. Existing code is migrated incrementally; no destructive rewrite.
2. UI never talks directly to SQLite or Firestore.
3. Dependency direction: Presentation -> Application -> Domain -> Repository abstraction; Data implements repositories.
4. Offline-first: successful business writes persist locally first; cloud synchronization is resilient and retryable.
5. Full Cloud Restore remains backward compatible while v2 schemas are introduced with explicit schema versions/migrations.
6. Every user-visible system string is localized in Vietnamese (vi), Lao (lo), and English (en). User-entered content is never auto-translated by storage code.
7. Authorization is enforced by permission + data scope, not merely by hiding UI.
8. Every destructive or sensitive operation has authorization, validation and auditability.
9. Business entities use stable IDs and explicit relationships. Referential integrity is validated before local/cloud replacement.
10. Each feature contract is frozen before implementation: entities, relationships, permissions, local schema, cloud schema, sync/restore, business rules, UI states, localization keys and tests.

## Feature map

- core: bootstrap, routing, design system, localization, auth, RBAC, local DB, cloud sync, offline queue, notifications, files/images, audit log
- dashboard: role-aware home dashboard and quick actions
- farm: farms, fields/land parcels, maps, GPS measurement, boundary history, Google Earth interoperability
- production: seasons, production logs, inputs, harvest, yield
- workforce: employees, teams, memberships, roles, permissions
- tasks: tasks, assignments, calendar, progress, checklist, completion evidence
- chat: direct/team/task/field conversations, messages, attachments, notifications
- machinery: machines, assignment, activity, maintenance, costs
- inventory: catalogue, stock, inbound/outbound/adjustment transaction ledger
- fuel: fuel stock, receipt, issue, machine usage, costs
- finance: income, expense, production costs, receivables/payables, cash flow
- reports: production/cost/yield/workforce/machinery/inventory reports and exports
- ai: assistant, analysis, alerts, recommendations
- cloud_backup: sync, restore, backup, conflicts, status
- settings: profile, farm, language, permissions, notifications, cloud, system

## Standard feature layout

lib/features/<feature>/
  data/
    models/
    local/
    remote/
    repositories/
  domain/
    entities/
    repositories/
    usecases/
  application/
    controllers/
    states/
  presentation/
    screens/
    widgets/
    dialogs/

Shared cross-feature code belongs in lib/core only when it is genuinely generic.

## Main navigation

Home | Modules | Quick Create | Reports | Profile

Home is not a catalogue of every module. It contains role-aware KPIs, assigned/urgent work, alerts, recent activity and quick actions. Chat/notifications are accessible from the app shell/header and contextually from tasks, teams and fields.

## Implementation gate

A feature is not complete until:
- domain rules are implemented;
- local persistence is implemented and tested;
- cloud mapping/sync/restore is implemented where applicable;
- RBAC/data scope is enforced;
- vi/lo/en localization is complete;
- loading/empty/error/offline states exist;
- unit/repository/widget/integration tests required by the feature contract pass;
- old data has a migration/compatibility path.
