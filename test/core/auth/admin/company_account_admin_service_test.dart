import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/auth/admin/company_account_admin_service.dart';
import 'package:agrico_deepseek/core/auth/company_membership.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';

class Repository implements CompanyAccountAdminRepository {
  int reads = 0, writes = 0;
  int? revision;
  String? actor, reason;
  CompanyAccountRecord? saved;
  @override
  Future<List<CompanyAccountRecord>> list(String farmId) async {
    reads++;
    return [];
  }

  @override
  Future<List<AccountAuditRecord>> audit(String farmId) async {
    reads++;
    return [];
  }

  @override
  Future<void> save({
    required String actorUid,
    required CompanyAccountRecord record,
    required int? expectedRevision,
    required String reason,
  }) async {
    writes++;
    saved = record;
    revision = expectedRevision;
    actor = actorUid;
    this.reason = reason;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 3);
  AuthorizationSubject admin({
    Set<String>? permissions,
    Set<DataScope>? scopes,
    bool expired = false,
  }) => AuthorizationSubject(
    userId: 'admin',
    membershipId: 'admin',
    farmId: 'local-farm',
    permissionCodes:
        permissions ??
        {
          PermissionCodes.accountView,
          PermissionCodes.accountManage,
          PermissionCodes.roleManage,
        },
    dataScopes: scopes ?? {DataScope.allFarm},
    validUntil: now.add(Duration(days: expired ? -1 : 1)),
  );
  CompanyAccountRecord record({
    String uid = 'worker',
    String farm = 'local-farm',
    bool active = true,
    DateTime? deadline,
    List<RoleAssignment>? roles,
    String name = 'Worker',
    Set<String> extras = const {},
    Set<DataScope> extraScopes = const {},
    Set<String> fields = const {},
  }) {
    final until = deadline ?? now.add(const Duration(days: 7));
    return CompanyAccountRecord(
      displayName: name,
      membership: CompanyMembership(
        profile: CompanyAccessProfile(
          userId: uid,
          membershipId: uid,
          farmId: farm,
          active: active,
          roles: roles ?? [RoleAssignment(CompanyRole.machineOperator)],
          extraPermissions: extras,
          extraPermissionScopes: extraScopes,
          fieldIds: fields,
        ),
        offlineUntil: until,
      ),
    );
  }

  Matcher failure(String code) =>
      isA<AccountAdminFailure>().having((e) => e.code, 'code', code);
  late Repository repository;
  late CompanyAccountAdminService service;
  setUp(() {
    repository = Repository();
    service = CompanyAccountAdminService(
      repository: repository,
      subject: admin(),
      clock: () => now,
    );
  });
  test(
    'save forwards trusted actor and expected revision and preserves scoped role',
    () async {
      final value = record(fields: {'parcel-a'});
      await service.save(
        record: value,
        expectedRevision: 4,
        reason: '  Transfer team  ',
      );
      expect(repository.actor, 'admin');
      expect(repository.revision, 4);
      expect(repository.reason, 'Transfer team');
      final subject = repository.saved!.membership.profile.subject(now: now);
      expect(subject.assignedFieldIds, {'parcel-a'});
      expect(
        subject.permissionScopes[PermissionCodes.taskView],
        contains(DataScope.assignedTasks),
      );
      expect(
        subject.permissionScopes[PermissionCodes.taskView],
        isNot(contains(DataScope.allFarm)),
      );
    },
  );
  test('viewer cannot mutate even if UI calls service directly', () async {
    service = CompanyAccountAdminService(
      repository: repository,
      subject: admin(permissions: {PermissionCodes.accountView}),
      clock: () => now,
    );
    await expectLater(
      service.save(record: record(), expectedRevision: null, reason: 'grant'),
      throwsA(failure('denied')),
    );
    expect(repository.writes, 0);
  });
  test('expired cached admin cannot read or mutate', () async {
    service = CompanyAccountAdminService(
      repository: repository,
      subject: admin(expired: true),
      clock: () => now,
    );
    expect(() => service.list(), throwsA(failure('denied')));
    await expectLater(
      service.save(record: record(), expectedRevision: null, reason: 'grant'),
      throwsA(failure('denied')),
    );
    expect(repository.reads + repository.writes, 0);
  });
  test('farm administration requires actual farm scope', () async {
    service = CompanyAccountAdminService(
      repository: repository,
      subject: admin(scopes: {DataScope.own}),
      clock: () => now,
    );
    expect(() => service.list(), throwsA(failure('denied')));
  });
  test('self editing and cross farm changes refused', () async {
    for (final value in [record(uid: 'admin'), record(farm: 'other')]) {
      await expectLater(
        service.save(record: value, expectedRevision: 0, reason: 'change'),
        throwsA(failure('identity')),
      );
    }
    expect(repository.writes, 0);
  });
  test('empty reason and name refused', () async {
    await expectLater(
      service.save(record: record(), expectedRevision: 0, reason: ' '),
      throwsA(failure('invalid')),
    );
    await expectLater(
      service.save(
        record: record(name: ''),
        expectedRevision: 0,
        reason: 'change',
      ),
      throwsA(failure('invalid')),
    );
  });
  test('duplicate role, empty scopes and roleless profile refused', () async {
    for (final roles in <List<RoleAssignment>>[
      [],
      [RoleAssignment(CompanyRole.director, scopes: {})],
      [
        RoleAssignment(CompanyRole.director),
        RoleAssignment(CompanyRole.director),
      ],
    ]) {
      await expectLater(
        service.save(
          record: record(roles: roles),
          expectedRevision: 0,
          reason: 'change',
        ),
        throwsA(failure('invalid')),
      );
    }
  });
  test('extra permission needs explicit scope', () async {
    await expectLater(
      service.save(
        record: record(extras: {PermissionCodes.fieldEdit}),
        expectedRevision: 0,
        reason: 'change',
      ),
      throwsA(failure('invalid')),
    );
  });
  test(
    'active expired lease refused but locking expired account allowed',
    () async {
      await expectLater(
        service.save(
          record: record(deadline: now),
          expectedRevision: 0,
          reason: 'change',
        ),
        throwsA(failure('deadline')),
      );
      await service.save(
        record: record(
          active: false,
          deadline: now.subtract(const Duration(days: 1)),
        ),
        expectedRevision: 0,
        reason: 'Lock account',
      );
      expect(repository.saved!.membership.profile.active, false);
    },
  );
  test('scope ID count and empty ID validation', () async {
    for (final fields in [
      {' '},
      {for (var i = 0; i < 101; i++) 'parcel-$i'},
    ]) {
      await expectLater(
        service.save(
          record: record(fields: fields),
          expectedRevision: 0,
          reason: 'change',
        ),
        throwsA(failure('invalid')),
      );
    }
  });
}
