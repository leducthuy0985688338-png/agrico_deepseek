import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_snapshot.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_projection.dart';
import 'package:agrico_deepseek/features/integration/presentation/production_cost_panel.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required bool permission,
    required bool complete,
  }) async {
    final tables = <String, List<Map<String, Object?>>>{
      if (complete)
        for (final t in ProductionCostProjection.requiredTables) t: [],
    };
    tables['land_parcels'] = [
      {'id': 'parcel', 'farm_id': 'f', 'parcel_code': 'LO-PRIVATE'},
    ];
    tables['production_plans_v1'] = [
      {
        'id': 'plan',
        'farm_id': 'f',
        'parcel_id': 'parcel',
        'currency': 'VND',
        'code': 'KH-PRIVATE',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductionCostPanel(
              snapshot: IntegrationSnapshot(
                farm: 'f',
                period: '2026-10',
                tables: tables,
              ),
              canView: () => permission,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'insufficient source coverage shows unavailable not a false zero total',
    (tester) async {
      await open(tester, permission: true, complete: false);
      await tester.tap(
        find.byKey(const ValueKey('production-cost-parcel-parcel')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('CHƯA ĐỦ DỮ LIỆU'), findsWidgets);
      expect(find.text('VND'), findsWidgets);
      expect(find.text('LAK'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty covered data is distinct from missing data', (
    tester,
  ) async {
    await open(tester, permission: true, complete: true);
    expect(find.textContaining('Không phát sinh'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('production-cost-parcel-parcel')),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('denied scope reveals no parcel or plan identifiers', (
    tester,
  ) async {
    await open(tester, permission: false, complete: true);
    expect(find.text('Không có quyền xem'), findsOneWidget);
    expect(find.text('LO-PRIVATE'), findsNothing);
    expect(find.text('KH-PRIVATE'), findsNothing);
  });
}
