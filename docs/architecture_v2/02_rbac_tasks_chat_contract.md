# AGRICO v2 — RBAC, Task Assignment & Chat Contract

Status: APPROVED

## Authorization model

Authorization decision = authenticated user + farm membership + role permissions + data scope + resource context.

Default roles are templates, not hard-coded authorization branches:
- owner
- farmManager
- teamLeader
- employee
- accountant
- warehouseKeeper
- viewer

A farm may later define custom roles without changing feature code.

Data scopes:
- allFarm
- team
- assignedFields
- assignedTasks
- own

Sensitive operations must be checked in application/domain authorization services even when UI actions are hidden.

## Core membership entities

FarmMembership:
- id, farmId, userId, employeeId?
- roleId
- teamIds[]
- active
- joinedAt, endedAt?

Role:
- id, farmId? (null for system template)
- code, displayNameKey
- permissionCodes[]

Team:
- id, farmId, name
- leaderMembershipId?
- active

## Task aggregate

Task:
- id, farmId
- title, description?
- fieldId?, seasonId?
- createdByMembershipId
- assignedTeamId?
- assigneeMembershipIds[]
- machineIds[]
- inventoryReservation/usage references where applicable
- priority
- status
- startAt?, dueAt?, completedAt?
- checklist[]
- completionEvidence[]
- conversationId?
- createdAt, updatedAt
- schemaVersion

TaskStatus:
- draft
- assigned
- accepted
- inProgress
- blocked
- completed
- verified
- cancelled

Task assignment changes are auditable. Completion may require evidence/verification according to farm policy.

## Chat model

Conversation types:
- direct
- team
- task
- field
- farm

Conversation:
- id, farmId, type
- memberIds[] or derived membership rule
- teamId?/taskId?/fieldId?
- title?
- createdBy, createdAt
- lastMessageAt?

Message:
- id, conversationId, farmId
- senderMembershipId
- body?
- attachmentIds[]
- replyToMessageId?
- systemEventType?
- createdAt
- editedAt?
- deletedAt?
- schemaVersion

System events can represent task assignment/status changes, but localized display text is generated client-side from event type + structured payload; translated strings are not persisted as canonical data.

## Integration rules

- Creating a task may create/link a task conversation.
- Task participants gain conversation access only according to authorization rules.
- Removing an assignee updates future access according to retention policy; historical messages are not silently deleted.
- A field conversation requires access to that field.
- Team conversation access follows active team membership.
- Direct conversation participants are explicit.
- Chat cannot be used to bypass field/task data scope.

## Notification events

Examples:
- taskAssigned
- taskDueSoon
- taskOverdue
- taskStatusChanged
- taskCompleted
- taskVerified
- chatMessageReceived
- mentionedInChat

Notifications store structured event data. vi/lo/en text is rendered through localization keys.

## Minimum permission families

workforce.view / workforce.manage
role.view / role.manage
task.view / task.create / task.edit / task.assign / task.complete / task.verify / task.delete
chat.view / chat.send / chat.create_group / chat.manage_group
field.view / field.edit / field.measure / field.boundary.edit / field.boundary.verify
inventory.view / inventory.manage / inventory.issue
machine.view / machine.manage / machine.assign
finance.view / finance.manage
report.view / report.export
cloud.sync / cloud.restore
settings.view / settings.manage

## Test contract

- role template and custom role permission evaluation;
- every data scope evaluation;
- task assignment and status transition rules;
- unauthorized task/field access denied below UI layer;
- task conversation linkage;
- team/direct/field conversation membership rules;
- notification event serialization;
- local-first task/chat writes and sync retry;
- restore relationship validation;
- vi/lo/en localization key coverage for system events and statuses.
