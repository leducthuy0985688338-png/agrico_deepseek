import '../core/permissions/live_authorization.dart';
import 'package:flutter/foundation.dart';

import '../core/backup/local_backup_access.dart';
import '../core/permissions/authorization.dart';

/// Expose the implemented V2 modules, and recheck the live session on tap.
Map<String, VoidCallback> v2ResourceModuleRoutes({
  required AuthorizationSubject subject,
  required AuthorizationSubject? Function() currentSubject,
  required VoidCallback openMachines,
  required VoidCallback openWorkers,
  required VoidCallback openInventory,
  required VoidCallback openBackup,
}) {
  bool allowed(String key) {
    final live = currentSubject();
    if (live == null ||
        live.userId != subject.userId ||
        live.membershipId != subject.membershipId ||
        live.farmId != subject.farmId) {
      return false;
    }
    if (key == 'backup') {
      return LocalBackupAccess(currentSubject: () => live).canOpen;
    }
    final guard = LiveAuthorization(currentSubject);
    if (key == 'warehouse')
      return guard.canEnter(subject, PermissionCodes.inventoryView);
    final domainPermission = key == 'machines'
        ? PermissionCodes.machineView
        : PermissionCodes.employeeView;
    return guard.canEnter(subject, domainPermission) ||
        guard.can(subject, PermissionCodes.catalogView);
  }

  final candidates = <String, VoidCallback>{
    'machines': openMachines,
    'employees': openWorkers,
    'warehouse': openInventory,
    'backup': openBackup,
  };
  return {
    for (final entry in candidates.entries)
      if (allowed(entry.key))
        entry.key: () {
          if (allowed(entry.key)) entry.value();
        },
  };
}
