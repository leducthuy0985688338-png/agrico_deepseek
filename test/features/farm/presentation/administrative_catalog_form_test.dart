import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
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
    await tester.enterText(find.byType(TextFormField).first, 'LA-SVK-NONG-TAKO-H001-001');
    await tester.enterText(find.byType(TextFormField).at(1), 'Test parcel');
    await tester.dragUntilVisible(find.byKey(const Key('save-parcel')),
        find.byType(ListView), const Offset(0, -300));
    await tester.tap(find.byKey(const Key('save-parcel')));
    await tester.pumpAndSettle();
    expect(submitted?.village, 'Ta Ko');
    expect([submitted?.countryCode, submitted?.provinceCode,
      submitted?.districtCode, submitted?.villageCode],
      ['LA', 'SVK', 'NONG', 'TAKO']);
  });
}
