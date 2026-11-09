import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_form_screen.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
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

  for (final target in ParcelLayer.values) {
    testWidgets('production form selects ${target.name} and retains boundary', (
      tester,
    ) async {
      LandParcelFormValue? submitted;
      final boundary = LandParcelBoundaryDraft(
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16, longitude: 106),
          Wgs84Vertex(latitude: 16, longitude: 106.001),
          Wgs84Vertex(latitude: 16.001, longitude: 106.001),
          Wgs84Vertex(latitude: 16.001, longitude: 106),
        ]),
        source: BoundarySource.gps,
      );
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
            productionProjectId: 'agrico-nong',
            productionProjectCode: 'AGR-NONG',
            boundaryDraft: boundary,
            onSubmit: (value) async {
              submitted = value;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('production-create-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standalone plot').last);
      await tester.pumpAndSettle();
      expect(find.text('Create standalone plot'), findsOneWidget);
      expect(
        find.byKey(const Key('production-standalone-code')),
        findsOneWidget,
      );
      expect(find.textContaining('AGR-NONG-T001'), findsOneWidget);
      if (target == ParcelLayer.landBlock) {
        await tester.tap(find.byKey(const Key('production-create-kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Production block').last);
        await tester.pumpAndSettle();
        expect(find.text('Create production block'), findsOneWidget);
        expect(find.byKey(const Key('production-block-code')), findsOneWidget);
        expect(find.textContaining('AGR-NONG-L001'), findsOneWidget);
      }
      expect(find.byKey(const Key('parcel-field-code')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('parcel-field-name')),
        'Production A',
      );
      await tester.dragUntilVisible(
        find.byKey(const Key('save-parcel')),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.tap(find.byKey(const Key('save-parcel')));
      await tester.pumpAndSettle();
      expect(submitted, isNotNull);
      expect(submitted!.productionKind, target);
      expect(submitted!.boundaryDraft, same(boundary));
      expect(submitted!.parcelCode, isEmpty);
      expect(submitted!.autoNumber, isFalse);
    });
  }
}
