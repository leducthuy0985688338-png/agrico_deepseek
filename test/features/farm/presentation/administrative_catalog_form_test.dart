import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final time = DateTime.utc(2026);
  AdministrativeUnit unit(String id, AdministrativeLevel level, String code,
          String name, String? parent) => AdministrativeUnit(
        id: id, level: level, code: code, name: name, parentId: parent,
        createdAt: time, createdBy: 'admin',
      );

  testWidgets('new parcel selects catalogued location and submits its codes',
      (tester) async {
    final units = [
      unit('la', AdministrativeLevel.country, 'LA', 'Lào', null),
      unit('svk', AdministrativeLevel.province, 'SVK', 'Savannakhet', 'la'),
      unit('nong', AdministrativeLevel.district, 'NONG', 'Nong', 'svk'),
      unit('tako', AdministrativeLevel.village, 'TAKO', 'Ta Ko', 'nong'),
    ];
    LandParcelFormValue? submitted;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
      ],
      home: LandParcelFormScreen(
        administrativeUnits: units,
        onSubmit: (value) async { submitted = value; },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('parcel-field-name')), 'Test parcel');
    await tester.dragUntilVisible(find.byKey(const Key('parcel-field-owner')),
        find.byType(ListView), const Offset(0, -300));
    await tester.enterText(find.byKey(const Key('parcel-field-owner')), 'Somphon');
    await tester.dragUntilVisible(find.byKey(const Key('save-parcel')),
        find.byType(ListView), const Offset(0, -300));
    await tester.tap(find.byKey(const Key('save-parcel')));
    await tester.pumpAndSettle();
    expect(submitted?.village, 'Ta Ko');
    expect(submitted?.autoNumber, isTrue);
    expect(submitted?.villageId, 'tako');
    expect(submitted?.ownerHouseholdId, isNull);
    expect([submitted?.countryCode, submitted?.provinceCode,
      submitted?.districtCode, submitted?.villageCode],
      ['LA', 'SVK', 'NONG', 'TAKO']);
  });
  testWidgets('existing household selection reuses its stable identity',
      (tester) async {
    final units = [
      unit('la', AdministrativeLevel.country, 'LA', 'Lào', null),
      unit('svk', AdministrativeLevel.province, 'SVK', 'Savannakhet', 'la'),
      unit('nong', AdministrativeLevel.district, 'NONG', 'Nong', 'svk'),
      unit('tako', AdministrativeLevel.village, 'TAKO', 'Ta Ko', 'nong'),
    ];
    final household = Household(
      id: 'household-1', farmId: 'local-farm',
      householdCode: 'H00001', headOfHouseholdName: 'Somphon',
      administrativeLocation: const AdministrativeLocation(
        countryName: 'Lào', countryCode: 'LA',
        provinceName: 'Savannakhet', provinceCode: 'SVK',
        districtName: 'Nong', districtCode: 'NONG',
        villageName: 'Ta Ko', villageCode: 'TAKO',
      ),
      active: true, createdAt: time, createdBy: 'admin',
      updatedAt: time, updatedBy: 'admin',
    );
    LandParcelFormValue? submitted;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
      ],
      home: LandParcelFormScreen(
        administrativeUnits: units,
        availableHouseholds: [household],
        onSubmit: (value) async { submitted = value; },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('parcel-field-name')), 'Second parcel');
    final picker = find.byKey(const Key('household-tako'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('H00001').last);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.byKey(const Key('save-parcel')),
        find.byType(ListView), const Offset(0, -300));
    await tester.tap(find.byKey(const Key('save-parcel')));
    await tester.pumpAndSettle();
    expect(submitted?.autoNumber, isTrue);
    expect(submitted?.ownerHouseholdId, household.id);
    expect(submitted?.ownerName, 'Somphon');
  });

}
