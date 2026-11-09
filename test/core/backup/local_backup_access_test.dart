import 'package:agrico_deepseek/core/backup/local_backup_access.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AuthorizationSubject subject({
    Set<String> permissions = const {PermissionCodes.localBackupExport},
    Set<DataScope> scopes = const {DataScope.allFarm},
    bool active = true,
    String farm = 'local-farm',
    DateTime? until,
    Map<String, Set<DataScope>> overrides = const {},
  }) => AuthorizationSubject(
    userId: 'admin', membershipId: 'member', farmId: farm,
    permissionCodes: permissions, dataScopes: scopes, active: active,
    validUntil: until ?? DateTime.now().add(const Duration(hours: 1)),
    permissionScopes: overrides,
  );

  test('whole database export requires an active full scope session', () async {
    AuthorizationSubject? current = subject();
    final access = LocalBackupAccess(currentSubject: () => current);
    var writes = 0;
    Future<void> operation() async { writes++; }
    await access.execute(PermissionCodes.localBackupExport, operation);
    expect(writes, 1);
    for (final denied in <AuthorizationSubject?>[
      null, subject(active: false), subject(farm: 'another-farm'),
      subject(permissions: {}), subject(scopes: {DataScope.own}),
      subject(until: DateTime.now().subtract(const Duration(seconds: 1))),
      subject(overrides: {PermissionCodes.localBackupExport: {}}),
    ]) {
      current = denied;
      expect(() => access.execute(PermissionCodes.localBackupExport, operation),
          throwsA(isA<LocalBackupPermissionException>()));
    }
    expect(writes, 1);
  });

  test('restore and export are independent and use the live session', () async {
    AuthorizationSubject? current = subject();
    final access = LocalBackupAccess(currentSubject: () => current);
    var schedules = 0;
    Future<void> schedule() async { schedules++; }
    expect(access.canOpen, isTrue);
    expect(() => access.execute(PermissionCodes.cloudRestore, schedule),
        throwsA(isA<LocalBackupPermissionException>()));
    current = subject(permissions: {PermissionCodes.cloudRestore});
    expect(access.can(PermissionCodes.localBackupExport), isFalse);
    await access.execute(PermissionCodes.cloudRestore, schedule);
    current = null;
    expect(() => access.execute(PermissionCodes.cloudRestore, schedule),
        throwsA(isA<LocalBackupPermissionException>()));
    expect(schedules, 1);
  });
}
