import 'package:agrico_deepseek/core/geography/application/manage_administrative_catalog.dart';
import 'package:agrico_deepseek/core/geography/data/sqlite_administrative_catalog.dart';
import 'package:agrico_deepseek/core/geography/domain/administrative_catalog_repository.dart';
import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/geography/presentation/administrative_catalog_screen.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late SqliteAdministrativeCatalog repository;
  late ManageAdministrativeCatalog service;
  late List<AdministrativeUnit> seedUnits;
  const subject = AuthorizationSubject(
    userId: 'admin', membershipId: 'admin-member', farmId: 'local-farm',
    permissionCodes: PermissionCodes.values,
    dataScopes: {DataScope.allFarm},
  );

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteAdministrativeCatalog.createSchema(database);
    repository = SqliteAdministrativeCatalog(database);
    await repository.seedInitialLocation();
    service = ManageAdministrativeCatalog(repository);
    seedUnits = await repository.all();
  });
  tearDown(() => database.close());

  testWidgets('new village is available after reopening the catalog screen',
      (tester) async {
    // Keep widget scheduling independent of sqflite's background isolate;
    // the repository tests below exercise real SQLite persistence.
    final memory = _MemoryCatalog(List.of(seedUnits));
    final widgetService = ManageAdministrativeCatalog(memory);
    Widget screen() => MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
      ],
      home: AdministrativeCatalogScreen(catalog: widgetService, subject: subject),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bản').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin-name')), 'Ban Mai');
    await tester.enterText(find.byKey(const Key('admin-code')), 'bm');
    await tester.tap(find.byKey(const Key('admin-save')));
    await tester.pumpAndSettle();

    final created = (await memory.all()).singleWhere((u) => u.code == 'BM');
    expect(created.level, AdministrativeLevel.village);
    expect(created.parentId, 'agrico-la-svk-nong');
    await tester.pump();
    await tester.dragUntilVisible(find.byKey(Key('admin-unit-${created.id}')),
        find.byKey(const Key('admin-list')), const Offset(0, -250));
    expect(find.byKey(Key('admin-unit-${created.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.byKey(Key('admin-unit-${created.id}')),
        find.byKey(const Key('admin-list')), const Offset(0, -250));
    expect(find.byKey(Key('admin-unit-${created.id}')), findsOneWidget);
  });

  test('catalog edit requires management permission and does not change seed',
      () async {
    const surveyor = AuthorizationSubject(
      userId: 'surveyor', membershipId: 'surveyor', farmId: 'local-farm',
      permissionCodes: {PermissionCodes.fieldCreate},
      dataScopes: {DataScope.allFarm},
    );
    await expectLater(
      service.add(subject: surveyor, level: AdministrativeLevel.village,
          parentId: 'agrico-la-svk-nong', name: 'Ban Mai', code: 'BM'),
      throwsStateError,
    );
    expect(await repository.all(), hasLength(4));
  });

  test('new province and district keep their parent scope and reject duplicates',
      () async {
    await service.add(subject: subject, level: AdministrativeLevel.province,
        parentId: 'agrico-la', name: 'New province', code: 'NP');
    final province = (await repository.all()).singleWhere((u) => u.code == 'NP');
    await service.add(subject: subject, level: AdministrativeLevel.district,
        parentId: province.id, name: 'New district', code: 'ND');
    final district = (await repository.all()).singleWhere((u) => u.code == 'ND');
    expect(district.parentId, province.id);
    await expectLater(
      service.add(subject: subject, level: AdministrativeLevel.district,
          parentId: province.id, name: 'Duplicate district', code: 'nd'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repository.all(), hasLength(6));
  });
}

class _MemoryCatalog implements AdministrativeCatalogRepository {
  _MemoryCatalog(this.units);
  final List<AdministrativeUnit> units;

  @override
  Future<List<AdministrativeUnit>> all() async => List.of(units);

  @override
  Future<void> add(AdministrativeUnit unit) async => units.add(unit);
}
