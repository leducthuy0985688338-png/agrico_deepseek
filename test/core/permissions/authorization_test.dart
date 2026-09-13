import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const authorization = AuthorizationService();

  AuthorizationSubject subject({
    Set<String> permissions = const {PermissionCodes.fieldView},
    Set<DataScope> scopes = const {DataScope.allFarm},
    Set<String> teamIds = const {},
    Set<String> fieldIds = const {},
    Set<String> taskIds = const {},
    bool active = true,
  }) => AuthorizationSubject(
    userId: 'user-1',
    membershipId: 'membership-1',
    farmId: 'farm-1',
    permissionCodes: permissions,
    dataScopes: scopes,
    teamIds: teamIds,
    assignedFieldIds: fieldIds,
    assignedTaskIds: taskIds,
    active: active,
  );

  test('requires active membership, permission and matching farm', () {
    const resource = ResourceContext(farmId: 'farm-1');

    expect(
      authorization.can(
        subject: subject(),
        permission: PermissionCodes.fieldView,
        resource: resource,
      ),
      isTrue,
    );
    expect(
      authorization.can(
        subject: subject(active: false),
        permission: PermissionCodes.fieldView,
        resource: resource,
      ),
      isFalse,
    );
    expect(
      authorization.can(
        subject: subject(),
        permission: PermissionCodes.fieldEdit,
        resource: resource,
      ),
      isFalse,
    );
    expect(
      authorization.can(
        subject: subject(),
        permission: PermissionCodes.fieldView,
        resource: const ResourceContext(farmId: 'farm-2'),
      ),
      isFalse,
    );
  });

  test('evaluates team, field, task and own scopes from resource context', () {
    final scopedSubject = subject(
      scopes: const {
        DataScope.team,
        DataScope.assignedFields,
        DataScope.assignedTasks,
        DataScope.own,
      },
      teamIds: const {'team-1'},
      fieldIds: const {'field-1'},
      taskIds: const {'task-1'},
    );

    for (final resource in const [
      ResourceContext(farmId: 'farm-1', teamId: 'team-1'),
      ResourceContext(farmId: 'farm-1', fieldId: 'field-1'),
      ResourceContext(farmId: 'farm-1', taskId: 'task-1'),
      ResourceContext(farmId: 'farm-1', ownerUserId: 'user-1'),
    ]) {
      expect(
        authorization.can(
          subject: scopedSubject,
          permission: PermissionCodes.fieldView,
          resource: resource,
        ),
        isTrue,
      );
    }

    expect(
      authorization.can(
        subject: scopedSubject,
        permission: PermissionCodes.fieldView,
        resource: const ResourceContext(
          farmId: 'farm-1',
          teamId: 'team-2',
          fieldId: 'field-2',
          taskId: 'task-2',
          ownerUserId: 'user-2',
        ),
      ),
      isFalse,
    );
  });
}
