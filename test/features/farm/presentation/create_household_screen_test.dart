import 'package:agrico_deepseek/core/geography/domain/administrative_catalog_repository.dart';
import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/create_household.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/create_household_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28);
  final units = [
    AdministrativeUnit(id: 'country', level: AdministrativeLevel.country,
      name: 'Lào', code: 'LA', createdAt: now, createdBy: 'admin'),
    AdministrativeUnit(id: 'province', level: AdministrativeLevel.province,
      parentId: 'country', name: 'Savannakhet', code: 'SVK',
      createdAt: now, createdBy: 'admin'),
    AdministrativeUnit(id: 'district', level: AdministrativeLevel.district,
      parentId: 'province', name: 'Nong', code: 'NONG',
      createdAt: now, createdBy: 'admin'),
    AdministrativeUnit(id: 'village', level: AdministrativeLevel.village,
      parentId: 'district', name: 'Ta Ko', code: 'TAKO',
      createdAt: now, createdBy: 'admin'),
  ];
  const subject = AuthorizationSubject(
    userId: 'user', membershipId: 'member', farmId: 'farm-1',
    permissionCodes: {PermissionCodes.householdCreate},
    dataScopes: {DataScope.allFarm},
  );

  testWidgets('creates a household from a catalog village without code entry',
      (tester) async {
    Household? saved;
    final catalog = _Catalog(units);
    final create = CreateHousehold(catalog, _Writer());
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Builder(builder: (context) => Scaffold(body: FilledButton(
        onPressed: () async {
          saved = await Navigator.push<Household>(context, MaterialPageRoute(
            builder: (_) => CreateHouseholdScreen(
              create: create, subject: subject, loadUnits: catalog.all),
          ));
        },
        child: const Text('Open'),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household-village')), findsOneWidget);
    expect(find.textContaining('H00001'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('household-head')), 'ນາງ ສົມພອນ');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('household-save')));
    await tester.tap(find.byKey(const Key('household-save')));
    await tester.pumpAndSettle();
    expect(saved?.householdCode, 'H00001');
    expect(saved?.administrativeLocation.villageCode, 'TAKO');
  });
}

class _Catalog implements AdministrativeCatalogRepository {
  _Catalog(this.units);
  final List<AdministrativeUnit> units;
  @override
  Future<List<AdministrativeUnit>> all() async => units;
  @override
  Future<void> add(AdministrativeUnit unit) async =>
      throw UnimplementedError();
}

class _Writer implements HouseholdCreationTransaction {
  @override
  Future<Household> create({required String farmId,
      required Household Function(String code) build}) async => build('H00001');
}
