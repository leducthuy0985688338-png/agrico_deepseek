import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/update_household_contact.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteLandSurveyRepository repository;
  late UpdateHouseholdContact update;
  final created = DateTime.utc(2026, 9, 1);
  const editor = AuthorizationSubject(
    userId: 'user', membershipId: 'editor', farmId: 'farm-1',
    permissionCodes: {PermissionCodes.householdEdit},
    dataScopes: {DataScope.allFarm},
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandSurveyRepository.createSchema(db);
    repository = SqliteLandSurveyRepository(db);
    update = UpdateHouseholdContact(repository);
    await repository.createHousehold(Household(
      id: 'h1', farmId: 'farm-1', householdCode: 'H00001',
      headOfHouseholdName: 'Old name', phone: '123',
      alternativeContact: 'Old contact',
      administrativeLocation: const AdministrativeLocation(
        countryName: 'Lào', countryCode: 'LA',
        provinceName: 'Savannakhet', provinceCode: 'SVK',
        districtName: 'Nong', districtCode: 'NONG',
        villageName: 'Ta Ko', villageCode: 'TAKO',
      ),
      active: true, address: 'Old address', notes: 'Keep notes',
      createdAt: created, createdBy: 'creator',
      updatedAt: created, updatedBy: 'creator',
    ));
  });
  tearDown(() => db.close());

  test('edits and clears contact while preserving identity and location', () async {
    final saved = await update.execute(
      subject: editor, householdId: 'h1', headName: ' ນາງ ສົມພອນ ',
      phone: '  ', alternativeContact: ' 020123 ',
    );
    final reopened = (await repository.getHousehold('h1'))!;
    expect(saved.headOfHouseholdName, 'ນາງ ສົມພອນ');
    expect(reopened.phone, isNull);
    expect(reopened.alternativeContact, '020123');
    expect(reopened.householdCode, 'H00001');
    expect(reopened.administrativeLocation.villageCode, 'TAKO');
    expect(reopened.address, 'Old address');
    expect(reopened.notes, 'Keep notes');
    expect(reopened.createdAt, created);
    expect(reopened.createdBy, 'creator');
    expect(reopened.updatedBy, 'editor');
  });

  test('rejects unauthorized, blank and cross-farm updates without mutation',
      () async {
    await expectLater(update.execute(
      subject: const AuthorizationSubject(
        userId: 'u', membershipId: 'm', farmId: 'farm-1',
        permissionCodes: {PermissionCodes.fieldView},
        dataScopes: {DataScope.allFarm},
      ), householdId: 'h1', headName: 'Changed', phone: '',
      alternativeContact: '',
    ), throwsStateError);
    await expectLater(update.execute(
      subject: editor, householdId: 'h1', headName: '  ', phone: '',
      alternativeContact: '',
    ), throwsFormatException);
    await expectLater(update.execute(
      subject: const AuthorizationSubject(
        userId: 'u', membershipId: 'm', farmId: 'other',
        permissionCodes: {PermissionCodes.householdEdit},
        dataScopes: {DataScope.allFarm},
      ), householdId: 'h1', headName: 'Changed', phone: '',
      alternativeContact: '',
    ), throwsStateError);
    expect((await repository.getHousehold('h1'))!.headOfHouseholdName,
        'Old name');
  });
}
