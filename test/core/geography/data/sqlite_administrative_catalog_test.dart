import 'package:agrico_deepseek/core/geography/data/sqlite_administrative_catalog.dart';
import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteAdministrativeCatalog repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteAdministrativeCatalog.createSchema(db);
    repository = SqliteAdministrativeCatalog(db);
  });
  tearDown(() async => db.close());

  AdministrativeUnit village(String id, String parent, String code) =>
      AdministrativeUnit(
        id: id, parentId: parent, level: AdministrativeLevel.village,
        name: id, code: code, createdAt: DateTime.utc(2026), createdBy: 'admin',
      );

  test('seed survives repeat and reopening the catalog', () async {
    await repository.seedInitialLocation();
    await repository.seedInitialLocation();
    final units = await repository.all();
    expect(units, hasLength(4));
    final catalog = await repository.loadCatalog();
    expect(catalog.codeFor('agrico-la-svk-nong-tako',
      level: AdministrativeLevel.village,
      parentId: 'agrico-la-svk-nong'), 'TAKO');
  });

  test('new village belongs to selected district and duplicate code fails', () async {
    await repository.seedInitialLocation();
    await repository.add(village('village-other', 'agrico-la-svk-nong', 'OTHER'));
    final catalog = await repository.loadCatalog();
    expect(catalog.codeFor('village-other', parentId: 'agrico-la-svk-nong'), 'OTHER');
    await expectLater(
      repository.add(village('village-duplicate', 'agrico-la-svk-nong', 'OTHER')),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repository.all(), hasLength(5));
  });

  test('wrong-level and missing parents do not create catalog entries', () async {
    await repository.seedInitialLocation();
    await expectLater(repository.add(village('wrong', 'agrico-la-svk', 'WRONG')),
        throwsFormatException);
    await expectLater(repository.add(village('missing', 'missing', 'MISSING')),
        throwsFormatException);
    expect(await repository.all(), hasLength(4));
  });
}
