import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('production block submits without a village or manual code', (
    tester,
  ) async {
    LandParcelFormValue? submitted;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: LandParcelFormScreen(
          landOnly: true,
          productionProjectCode: 'AGR-NONG',
          onSubmit: (value) async {
            submitted = value;
          },
        ),
      ),
    );
    expect(find.text('Create production block'), findsOneWidget);
    expect(find.byKey(const Key('production-block-code')), findsOneWidget);
    expect(find.byKey(const Key('parcel-field-code')), findsNothing);
    expect(find.byKey(const Key('parcel-field-village')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('parcel-field-name')),
      'Block A',
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('save-parcel')),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.tap(find.byKey(const Key('save-parcel')));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!.name, 'Block A');
    expect(submitted!.villageId, isNull);
    expect(submitted!.autoNumber, isFalse);
    expect(submitted!.parcelCode, isEmpty);
  });
}
