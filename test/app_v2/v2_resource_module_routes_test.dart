import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:agrico_deepseek/app_v2/agrico_app_shell.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/app_v2/v2_resource_module_routes.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';

void main() {
  AuthorizationSubject actor({
    Set<String> permissions = const {
      PermissionCodes.catalogView,
      PermissionCodes.inventoryView,
      PermissionCodes.localBackupExport,
    },
    Set<DataScope> scopes = const {DataScope.allFarm},
    Map<String, Set<DataScope>> overrides = const {},
    bool active = true,
    String farm = 'local-farm',
    DateTime? deadline,
  }) => AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: farm,
    permissionCodes: permissions,
    dataScopes: scopes,
    permissionScopes: overrides,
    active: active,
    validUntil: deadline ?? DateTime.now().add(const Duration(hours: 1)),
  );

  Map<String, void Function()> routes(
    AuthorizationSubject subject,
    AuthorizationSubject? Function() live,
    List<String> opened,
  ) => v2ResourceModuleRoutes(
    subject: subject,
    currentSubject: live,
    openMachines: () => opened.add('machines'),
    openWorkers: () => opened.add('employees'),
    openInventory: () => opened.add('warehouse'),
    openBackup: () => opened.add('backup'),
  );

  testWidgets('Modules exposes the four V2 routes with working callbacks', (
    tester,
  ) async {
    final subject = actor();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ModulesV2(
            subject: subject,
            openLandParcels: () {},
            legacyRoutes: routes(subject, () => subject, opened),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in ['employees', 'machines', 'warehouse', 'backup']) {
      final tile = find.byKey(Key('module-v2-$key'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(tile).enabled, isTrue);
      await tester.tap(tile);
      await tester.pump();
    }
    expect(opened, ['employees', 'machines', 'warehouse', 'backup']);
    expect(find.text('Nhân công'), findsOneWidget);
    final unsupported = find.byKey(const Key('module-v2-fuel'));
    expect(tester.widget<ListTile>(unsupported).enabled, isFalse);
  });

  testWidgets('Modules exposes the four V2 routes with working callbacks', (
    tester,
  ) async {
    final subject = actor();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ModulesV2(
            subject: subject,
            openLandParcels: () {},
            legacyRoutes: routes(subject, () => subject, opened),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in ['employees', 'machines', 'warehouse', 'backup']) {
      final tile = find.byKey(Key('module-v2-$key'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(tile).enabled, isTrue);
      if (key == 'employees') expect(find.text('Nhân công'), findsOneWidget);
      await tester.tap(tile);
      await tester.pump();
    }
    expect(opened, ['employees', 'machines', 'warehouse', 'backup']);
    expect(routes(subject, () => subject, opened), isNot(contains('fuel')));
  });

  test('authorized modules open their distinct destinations', () {
    final subject = actor();
    final opened = <String>[];
    final result = routes(subject, () => subject, opened);
    expect(
      result.keys,
      unorderedEquals(['machines', 'employees', 'warehouse', 'backup']),
    );
    for (final callback in result.values) {
      callback();
    }
    expect(opened, ['machines', 'employees', 'warehouse', 'backup']);
  });

  test('catalog viewing does not grant inventory or backup access', () {
    final subject = actor(permissions: {PermissionCodes.catalogView});
    expect(
      routes(subject, () => subject, []).keys,
      unorderedEquals(['machines', 'employees']),
    );
  });

  test('narrow scope and explicit permission scope deny whole-farm reads', () {
    final narrow = actor(scopes: {DataScope.assignedFields});
    expect(routes(narrow, () => narrow, []), isEmpty);
    final override = actor(
      overrides: {
        PermissionCodes.catalogView: {},
        PermissionCodes.inventoryView: {},
        PermissionCodes.localBackupExport: {},
      },
    );
    expect(routes(override, () => override, []), isEmpty);
  });

  test('inactive and expired sessions expose no module callbacks', () {
    for (final subject in [
      actor(active: false),
      actor(deadline: DateTime.now().subtract(const Duration(seconds: 1))),
    ]) {
      expect(routes(subject, () => subject, []), isEmpty);
    }
  });

  test('saved callbacks recheck revoked permissions and sign-out', () {
    final initial = actor();
    AuthorizationSubject? live = initial;
    final opened = <String>[];
    final result = routes(initial, () => live, opened);
    live = actor(permissions: {});
    for (final callback in result.values) {
      callback();
    }
    live = null;
    for (final callback in result.values) {
      callback();
    }
    expect(opened, isEmpty);
  });

  test('saved callbacks reject a changed farm and expired lease', () {
    final initial = actor();
    AuthorizationSubject? live = initial;
    final opened = <String>[];
    final result = routes(initial, () => live, opened);
    live = actor(farm: 'another-farm');
    for (final callback in result.values) {
      callback();
    }
    live = actor(deadline: DateTime.now().subtract(const Duration(seconds: 1)));
    for (final callback in result.values) {
      callback();
    }
    expect(opened, isEmpty);
  });

  test('backup respects existing local-farm restriction', () {
    final subject = actor(farm: 'farm-2');
    expect(
      routes(subject, () => subject, []).keys,
      unorderedEquals(['machines', 'employees', 'warehouse']),
    );
  });
}
