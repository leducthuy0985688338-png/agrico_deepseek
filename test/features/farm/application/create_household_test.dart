import 'package:agrico_deepseek/core/geography/data/sqlite_administrative_catalog.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/create_household.dart';
import 'package:agrico_deepseek/features/farm/data/adapters/sqlite_household_creation_transaction.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteLandSurveyRepository households;
  late CreateHousehold create;
  const subject = AuthorizationSubject(
    userId: 'user', membershipId: 'surveyor', farmId: 'farm-1',
    permissionCodes: {PermissionCodes.householdCreate},
    dataScopes: {DataScope.allFarm},
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandSurveyRepository.createSchema(db);
    await SqliteParcelNumberSequence.createSchema(db);
    await SqliteAdministrativeCatalog.createSchema(db);
    final catalog = SqliteAdministrativeCatalog(db);
    await catalog.seedInitialLocation();
    households = SqliteLandSurveyRepository(db);
    create = CreateHousehold(catalog,
        SqliteHouseholdCreationTransaction(db));
  });
  tearDown(() => db.close());

  test('independent households get sequential farm codes and catalog location',
      () async {
    final first = await create.execute(subject: subject,
      villageId: 'agrico-la-svk-nong-tako', headName: ' ນາງ ສົມພອນ ',
      phone: ' 020123 ',
    );
    final second = await create.execute(subject: subject,
      villageId: 'agrico-la-svk-nong-tako', headName: 'Nguyễn Văn B');
    expect(first.householdCode, 'H00001');
    expect(second.householdCode, 'H00002');
    expect(first.headOfHouseholdName, 'ນາງ ສົມພອນ');
    expect(first.phone, '020123');
    expect(first.administrativeLocation.villageCode, 'TAKO');
    expect(first.administrativeLocation.districtCode, 'NONG');
    expect((await households.listHouseholds('farm-1')).length, 2);
  });

  test('invalid village or unauthorized user does not spend a number', () async {
    await expectLater(create.execute(subject: subject,
      villageId: 'missing', headName: 'Person'), throwsFormatException);
    await expectLater(create.execute(subject: const AuthorizationSubject(
      userId: 'user', membershipId: 'surveyor', farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.allFarm},
    ), villageId: 'agrico-la-svk-nong-tako', headName: 'Person'),
        throwsStateError);
    await expectLater(create.execute(subject: subject,
      villageId: 'agrico-la-svk-nong-tako', headName: '  '),
        throwsFormatException);
    expect((await households.listHouseholds('farm-1')), isEmpty);
    expect((await create.execute(subject: subject,
      villageId: 'agrico-la-svk-nong-tako', headName: 'Person'))
        .householdCode, 'H00001');
  });

  test('failed record write rolls the sequence back', () async {
    final adapter = SqliteHouseholdCreationTransaction(db);
    await expectLater(adapter.create(farmId: 'farm-1', build: (_) =>
        throw StateError('failed before insert')), throwsStateError);
    expect((await create.execute(subject: subject,
      villageId: 'agrico-la-svk-nong-tako', headName: 'Person'))
        .householdCode, 'H00001');
  });
}
