import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/auth/company_membership.dart';
import 'package:agrico_deepseek/core/auth/company_session.dart';
import 'package:agrico_deepseek/core/auth/file_company_session_store.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';

import 'company_auth_test_support.dart';

void main() {
  late Gateway gateway;
  late MemoryStore store;
  late CompanySessionService service;
  late DateTime now;
  setUp(() {
    gateway = Gateway();
    store = MemoryStore();
    now = start;
    service = CompanySessionService(
      gateway: gateway,
      store: store,
      clock: () => now,
    );
  });
  Future<void> login() => service.login('employee@company.example', 'correct');
  test('real credential gateway and server grant are both required', () async {
    await login();
    expect(service.subject.userId, 'user');
    expect(
      service.subject.permissionCodes,
      contains(PermissionCodes.catalogManage),
    );
    expect(
      service.subject.permissionCodes,
      isNot(contains(PermissionCodes.financeApprove)),
    );
    expect(service.offline, isFalse);
    expect(store.value!.verifiedAt, start);
    expect(store.value!.toJson().toString(), isNot(contains('correct')));
  });
  test('wrong password closes old session and clears cached rights', () async {
    await login();
    await expectLater(
      service.login('employee@company.example', 'wrong'),
      throwsA(isA<AccessFailure>()),
    );
    expect(store.value, isNull);
    expect(service.current, isNull);
    expect(gateway.uid, isNull);
  });
  test('first login is unavailable offline and creates no grant', () async {
    gateway.fetchError = const AccessUnavailable();
    await expectLater(login(), throwsA(isA<AccessUnavailable>()));
    expect(store.value, isNull);
    expect(gateway.uid, isNull);
  });
  test('offline restart restores only already verified identity', () async {
    await login();
    now = start.add(const Duration(hours: 2));
    gateway.fetchError = const AccessUnavailable();
    final reopened = CompanySessionService(
      gateway: gateway,
      store: store,
      clock: () => now,
    );
    expect(await reopened.restore(), isTrue);
    expect(reopened.offline, isTrue);
    expect(store.value!.verifiedAt, start);
    expect(store.value!.lastSeenAt, now);
    expect(
      store.value!.membership.offlineUntil,
      start.add(const Duration(days: 2)),
    );
  });
  test('no native identity means no offline entry', () async {
    await login();
    gateway.uid = null;
    expect(await service.restore(), isFalse);
    expect(store.value, isNull);
  });
  test('cached identity cannot cross accounts', () async {
    await login();
    gateway.uid = 'another';
    gateway.fetchError = const AccessUnavailable();
    await expectLater(service.restore(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('cache cannot cross Firebase projects', () async {
    await login();
    gateway.projectId = 'other';
    gateway.fetchError = const AccessUnavailable();
    await expectLater(service.restore(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('permission denial never falls back to cached administrator', () async {
    await login();
    gateway.fetchError = const AccessFailure('membershipDenied');
    await expectLater(service.restore(), throwsA(isA<AccessFailure>()));
    expect(service.current, isNull);
    expect(store.value, isNull);
  });
  test('inactive membership revokes cached access online', () async {
    await login();
    gateway.grant = membership(active: false);
    await expectLater(service.restore(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('wrong farm is rejected without migrating business records', () async {
    gateway.grant = membership(farm: 'another');
    await expectLater(login(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('wrong UID in server membership is rejected', () async {
    gateway.grant = membership(uid: 'another');
    await expectLater(login(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('expired offline session cannot reopen', () async {
    await login();
    now = start.add(const Duration(days: 2));
    gateway.fetchError = const AccessUnavailable();
    await expectLater(service.restore(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('an existing subject stops authorizing exactly at expiry', () async {
    await login();
    final subject = service.subject;
    final authorization = AuthorizationService(clock: () => now);
    bool can() => authorization.can(
      subject: subject,
      permission: PermissionCodes.catalogManage,
      resource: const ResourceContext(farmId: 'local-farm'),
    );
    expect(can(), isTrue);
    now = start.add(const Duration(days: 2));
    expect(can(), isFalse);
    expect(() => service.subject, throwsA(isA<AccessFailure>()));
  });
  test('rolling device clock back cannot reuse offline lease', () async {
    await login();
    now = start.add(const Duration(hours: 1));
    await service.checkpoint();
    now = start;
    gateway.fetchError = const AccessUnavailable();
    await expectLater(service.restore(), throwsA(isA<AccessFailure>()));
    expect(store.value, isNull);
  });
  test('checkpoint and logout never extend lease or retain rights', () async {
    await login();
    now = start.add(const Duration(hours: 1));
    await service.checkpoint();
    expect(
      store.value!.membership.offlineUntil,
      start.add(const Duration(days: 2)),
    );
    await service.logout();
    expect(store.value, isNull);
    expect(gateway.uid, isNull);
  });
  test(
    'online refresh replaces grants instead of unioning old rights',
    () async {
      await login();
      gateway.grant = CompanyMembership(
        profile: CompanyAccessProfile(
          userId: 'user',
          membershipId: 'user',
          farmId: 'local-farm',
          roles: [RoleAssignment(CompanyRole.fieldWorker)],
          taskIds: {'task'},
          offlineValidUntil: start.add(const Duration(days: 2)),
        ),
        offlineUntil: start.add(const Duration(days: 2)),
      );
      await service.restore();
      expect(
        service.subject.permissionCodes,
        isNot(contains(PermissionCodes.catalogManage)),
      );
      expect(service.subject.assignedTaskIds, {'task'});
    },
  );
  test('logout wins over a concurrent periodic checkpoint', () async {
    await login();
    now = start.add(const Duration(minutes: 1));
    await Future.wait([service.checkpoint(), service.logout()]);
    expect(service.current, isNull);
    expect(store.value, isNull);
    expect(gateway.uid, isNull);
  });
  test('membership round trip retains explicit scopes and denies', () {
    final original = membership();
    final copied = CompanyMembership.fromJson(original.toJson());
    expect(copied.toJson(), original.toJson());
  });
  test('unknown role, permission and invalid dates fail closed', () {
    final json = membership().toJson();
    expect(
      () => CompanyMembership.fromJson({
        ...json,
        'roles': [
          {'role': 'superUser'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => CompanyMembership.fromJson({
        ...json,
        'extraPermissions': ['unknown'],
      }),
      throwsFormatException,
    );
    expect(
      () => CompanyMembership.fromJson({...json, 'offlineUntil': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => CompanyMembership.fromJson({...json, 'active': 'true'}),
      throwsFormatException,
    );
  });
  test('file persistence survives reopening and clear removes cache', () async {
    final directory = await Directory.systemTemp.createTemp(
      'agrico-session-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/session.json');
    final first = FileCompanySessionStore(file);
    await login();
    await first.write(store.value!);
    final second = FileCompanySessionStore(file);
    expect((await second.read())!.toJson(), store.value!.toJson());
    await second.clear();
    expect(await first.read(), isNull);
  });
  test('corrupted cache is discarded', () async {
    final directory = await Directory.systemTemp.createTemp(
      'agrico-session-invalid-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/session.json');
    await file.writeAsString('{broken');
    expect(await FileCompanySessionStore(file).read(), isNull);
    expect(await file.exists(), isFalse);
  });
}
