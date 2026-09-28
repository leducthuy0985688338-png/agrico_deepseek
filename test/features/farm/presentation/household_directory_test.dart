import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/household_directory_query.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/household_directory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28);
  Household household(String id, String code, String name, String village) =>
      Household(
        id: id, farmId: 'farm-1', householdCode: code,
        headOfHouseholdName: name,
        administrativeLocation: AdministrativeLocation(
          countryName: 'Lào', provinceName: 'Savannakhet',
          districtName: 'Nong', villageName: village,
        ),
        active: true, createdAt: now, createdBy: 'member-1',
        updatedAt: now, updatedBy: 'member-1',
      );
  const allowed = AuthorizationSubject(
    userId: 'user-1', membershipId: 'member-1', farmId: 'farm-1',
    permissionCodes: {PermissionCodes.fieldView},
    dataScopes: {DataScope.allFarm},
  );

  test('query checks access before loading households in its farm', () async {
    final repository = _HouseholdRepository([
      household('one', 'H00001', 'ນາງ ສົມພອນ', 'Ta Ko'),
    ]);
    final query = HouseholdDirectoryQuery(repository);
    expect((await query.list(allowed)).single.householdCode, 'H00001');
    expect(repository.requestedFarmId, 'farm-1');

    const limited = AuthorizationSubject(
      userId: 'user-1', membershipId: 'member-1', farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.assignedFields},
    );
    await expectLater(query.list(limited), throwsStateError);
    expect(repository.calls, 1);
  });

  testWidgets('searches code, Unicode name and village without editing data',
      (tester) async {
    final repository = _HouseholdRepository([
      household('one', 'H00001', 'ນາງ ສົມພອນ', 'Ta Ko'),
      household('two', 'H00002', 'Nguyễn Văn B', 'Ban Mai'),
    ]);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: HouseholdDirectoryScreen(
        query: HouseholdDirectoryQuery(repository), subject: allowed),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household-one')), findsOneWidget);
    expect(find.byKey(const Key('household-two')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('household-search')), 'ສົມພອນ');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household-one')), findsOneWidget);
    expect(find.byKey(const Key('household-two')), findsNothing);

    await tester.enterText(find.byKey(const Key('household-search')), 'Ban Mai');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household-two')), findsOneWidget);
    expect(repository.calls, 1);
  });
}

class _HouseholdRepository implements LandSurveyRepository {
  _HouseholdRepository(this.values);
  final List<Household> values;
  String? requestedFarmId;
  int calls = 0;

  @override
  Future<List<Household>> listHouseholds(String farmId) async {
    requestedFarmId = farmId;
    calls++;
    return values.where((value) => value.farmId == farmId).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
