/// Scope of business data visible to a farm membership.
enum DataScope { allFarm, team, assignedFields, assignedTasks, own }

/// Stable permission codes. UI and domain services share these identifiers,
/// but authorization decisions must be made below the presentation layer.
abstract final class PermissionCodes {
  static const fieldView = 'field.view';
  static const fieldCreate = 'field.create';
  static const fieldEdit = 'field.edit';
  static const fieldDelete = 'field.delete';
  static const fieldMeasure = 'field.measure';
  static const fieldBoundaryEdit = 'field.boundary.edit';
  static const fieldBoundaryVerify = 'field.boundary.verify';
  static const fieldGoogleEarthImport = 'field.google_earth.import';
  static const fieldGoogleEarthExport = 'field.google_earth.export';
  static const taskView = 'task.view';
  static const taskCreate = 'task.create';
  static const taskEdit = 'task.edit';
  static const taskAssign = 'task.assign';
  static const taskComplete = 'task.complete';
  static const taskVerify = 'task.verify';
  static const chatView = 'chat.view';
  static const chatSend = 'chat.send';
  static const cloudSync = 'cloud.sync';
  static const cloudRestore = 'cloud.restore';
  static const administrativeCatalogManage = 'administrative_catalog.manage';

  static const values = <String>{
    fieldView,
    fieldCreate,
    fieldEdit,
    fieldDelete,
    fieldMeasure,
    fieldBoundaryEdit,
    fieldBoundaryVerify,
    fieldGoogleEarthImport,
    fieldGoogleEarthExport,
    taskView,
    taskCreate,
    taskEdit,
    taskAssign,
    taskComplete,
    taskVerify,
    chatView,
    chatSend,
    cloudSync,
    cloudRestore,
    administrativeCatalogManage,
  };
}

class AuthorizationSubject {
  const AuthorizationSubject({
    required this.userId,
    required this.membershipId,
    required this.farmId,
    required this.permissionCodes,
    required this.dataScopes,
    this.teamIds = const {},
    this.assignedFieldIds = const {},
    this.assignedTaskIds = const {},
    this.active = true,
  });

  final String userId;
  final String membershipId;
  final String farmId;
  final Set<String> permissionCodes;
  final Set<DataScope> dataScopes;
  final Set<String> teamIds;
  final Set<String> assignedFieldIds;
  final Set<String> assignedTaskIds;
  final bool active;
}

class ResourceContext {
  const ResourceContext({
    required this.farmId,
    this.ownerUserId,
    this.teamId,
    this.fieldId,
    this.taskId,
  });

  final String farmId;
  final String? ownerUserId;
  final String? teamId;
  final String? fieldId;
  final String? taskId;
}

class AuthorizationService {
  const AuthorizationService();

  bool can({
    required AuthorizationSubject subject,
    required String permission,
    required ResourceContext resource,
  }) {
    if (!subject.active ||
        subject.farmId != resource.farmId ||
        !subject.permissionCodes.contains(permission)) {
      return false;
    }

    return subject.dataScopes.any((scope) {
      switch (scope) {
        case DataScope.allFarm:
          return true;
        case DataScope.team:
          return resource.teamId != null &&
              subject.teamIds.contains(resource.teamId);
        case DataScope.assignedFields:
          return resource.fieldId != null &&
              subject.assignedFieldIds.contains(resource.fieldId);
        case DataScope.assignedTasks:
          return resource.taskId != null &&
              subject.assignedTaskIds.contains(resource.taskId);
        case DataScope.own:
          return resource.ownerUserId == subject.userId;
      }
    });
  }
}
