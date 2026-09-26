import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  final numbers = SqliteParcelNumberSequence();

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteParcelNumberSequence.createSchema(db);
    await db.execute('CREATE TABLE saved_codes (code TEXT PRIMARY KEY)');
  });
  tearDown(() async => db.close());

  Future<String> household() => db.transaction((tx) =>
      numbers.saveHousehold(tx: tx, farmId: 'farm',
          save: (code) async {
        await tx.insert('saved_codes', {'code': code});
        return code;
      }));

  Future<String> parcel(String village, int householdNumber) =>
      db.transaction((tx) => numbers.saveParcel(
        tx: tx, farmId: 'farm', villageId: village,
        householdNumber: householdNumber,
        countryCode: 'LA', provinceCode: 'SVK', districtCode: 'NONG',
        villageCode: village,
        save: (code) async {
          await tx.insert('saved_codes', {'code': code});
          return code;
        },
      ));

  test('households increment across villages; parcels restart in each household',
      () async {
    expect(await household(), 'H00001');
    expect(await household(), 'H00002');
    expect(await household(), 'H00003');
    expect(await parcel('TAKO', 1), 'LA-SVK-NONG-TAKO-H00001-001');
    expect(await parcel('TAKO', 1), 'LA-SVK-NONG-TAKO-H00001-002');
    expect(await parcel('TAKO', 2), 'LA-SVK-NONG-TAKO-H00002-001');
    expect(await parcel('OTHER', 3), 'LA-SVK-NONG-OTHER-H00003-001');
  });

  test('a different farm has an independent H00001', () async {
    expect(await household(), 'H00001');
    final other = await db.transaction((tx) => numbers.saveHousehold(
      tx: tx, farmId: 'other-farm', save: (code) async => code,
    ));
    expect(other, 'H00001');
  });

  test('failed save rolls back number and its record', () async {
    await expectLater(db.transaction((tx) => numbers.saveHousehold(
      tx: tx, farmId: 'farm',
      save: (_) async => throw StateError('write failed'),
    )), throwsStateError);
    expect(await household(), 'H00001');
    await expectLater(db.transaction((tx) => numbers.saveParcel(
      tx: tx, farmId: 'farm', villageId: 'TAKO', householdNumber: 1,
      countryCode: 'LA', provinceCode: 'SVK', districtCode: 'NONG',
      villageCode: 'TAKO',
      save: (_) async => throw StateError('parcel write failed'),
    )), throwsStateError);
    expect(await parcel('TAKO', 1), 'LA-SVK-NONG-TAKO-H00001-001');
  });

  test('v2 schema preserves old household allocation and allows number 1000', () async {
    await db.execute('''
      CREATE TABLE ${SqliteParcelNumberSequence.previousTable} (
        farm_id TEXT NOT NULL, village_id TEXT NOT NULL,
        household_number INTEGER NOT NULL, last_sequence INTEGER NOT NULL,
        PRIMARY KEY (farm_id, village_id, household_number)
      )
    ''');
    await db.insert(SqliteParcelNumberSequence.previousTable, {
      'farm_id': 'farm', 'village_id': 'TAKO',
      'household_number': 0, 'last_sequence': 999,
    });
    await SqliteParcelNumberSequence.createSchema(db);
    expect(await household(), 'H01000');
  });

  test('existing household numbers advance the farm counter without going back', () async {
    await db.execute('CREATE TABLE households '
        '(farm_id TEXT NOT NULL, household_code TEXT NOT NULL)');
    await db.insert('households', {
      'farm_id': 'farm', 'household_code': 'H00008',
    });
    await db.insert('households', {
      'farm_id': 'other-farm', 'household_code': 'H00200',
    });
    await SqliteParcelNumberSequence.reconcileExistingHouseholds(db);
    expect(await household(), 'H00009');
    await SqliteParcelNumberSequence.reconcileExistingHouseholds(db);
    expect(await household(), 'H00010');
  });

  test('exhaustion fails without wrapping', () async {
    await db.insert(SqliteParcelNumberSequence.table, {
      'farm_id': 'farm', 'village_id': '',
      'household_number': 0, 'last_sequence': 99999,
    });
    await expectLater(household(), throwsFormatException);
    expect(await db.query('saved_codes'), isEmpty);
  });
}
