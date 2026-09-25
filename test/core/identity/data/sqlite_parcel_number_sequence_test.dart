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
    expect(await household(), 'H001');
    expect(await household(), 'H002');
    expect(await household(), 'H003');
    expect(await parcel('TAKO', 1), 'LA-SVK-NONG-TAKO-H001-001');
    expect(await parcel('TAKO', 1), 'LA-SVK-NONG-TAKO-H001-002');
    expect(await parcel('TAKO', 2), 'LA-SVK-NONG-TAKO-H002-001');
    expect(await parcel('OTHER', 3), 'LA-SVK-NONG-OTHER-H003-001');
  });

  test('failed save rolls back number and its record', () async {
    await expectLater(db.transaction((tx) => numbers.saveHousehold(
      tx: tx, farmId: 'farm',
      save: (_) async => throw StateError('write failed'),
    )), throwsStateError);
    expect(await household(), 'H001');
    await expectLater(db.transaction((tx) => numbers.saveParcel(
      tx: tx, farmId: 'farm', villageId: 'TAKO', householdNumber: 1,
      countryCode: 'LA', provinceCode: 'SVK', districtCode: 'NONG',
      villageCode: 'TAKO',
      save: (_) async => throw StateError('parcel write failed'),
    )), throwsStateError);
    expect(await parcel('TAKO', 1), 'LA-SVK-NONG-TAKO-H001-001');
  });

  test('exhaustion fails without wrapping', () async {
    await db.insert(SqliteParcelNumberSequence.table, {
      'farm_id': 'farm', 'village_id': '',
      'household_number': 0, 'last_sequence': 999,
    });
    await expectLater(household(), throwsFormatException);
    expect(await db.query('saved_codes'), isEmpty);
  });
}
