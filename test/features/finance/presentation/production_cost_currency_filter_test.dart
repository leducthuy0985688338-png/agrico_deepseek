import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_report.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_period.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_parcel_filter.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/production_cost_summary_test.dart' as fixture;
import 'finance_document_details_test.dart' as app_fixture;

class _Store implements FinanceDocumentStore {
  int reads = 0;
  List<FinanceDocument> items = [
    fixture.document(
      'lak',
      1000000,
      parcelId: 'one',
      date: DateTime(2026, 10, 12),
    ),
    fixture.document(
      'vnd',
      2000000,
      parcelId: 'one',
      currency: 'VND',
      date: DateTime(2026, 10, 12),
    ),
    fixture.document(
      'other',
      3000000,
      parcelId: 'two',
      currency: 'VND',
      date: DateTime(2026, 10, 12),
    ),
    fixture.document(
      'old',
      4000000,
      parcelId: 'one',
      currency: 'VND',
      date: DateTime(2026, 9, 1),
    ),
    fixture.document('usd', 50, currency: 'USD', date: DateTime(2026, 10, 12)),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> chooseCurrency(WidgetTester tester, String value) async {
  final finder = find.byKey(const Key('costs-currency'));
  final field = tester.widget<DropdownButton<String>>(
    find.descendant(of: finder, matching: find.byType(DropdownButton<String>)),
  );
  final label =
      (field.items!.singleWhere((item) => item.value == value).child as Text)
          .data!;
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  late _Store store;
  late ProductionCostSummary summary;
  setUp(() {
    store = _Store();
    final actor = fixture.actor();
    summary = ProductionCostSummary(
      FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      ),
    );
  });
  test(
    'currency intersects parcel and period for totals documents and Excel',
    () async {
      final period = ProductionCostPeriod(
        from: DateTime(2026, 10, 12),
        to: DateTime(2026, 10, 12),
      );
      const parcel = ProductionCostParcelFilter.parcel('one');
      final snapshot = await summary.load(
        currency: 'VND',
        period: period,
        parcelFilter: parcel,
      );
      expect(snapshot.totals, {'VND': 2000000});
      expect(snapshot.groups.single.documents.single.id, 'vnd');
      expect(snapshot.availableCurrencies, {'LAK', 'VND', 'USD'});
      final workbook = await ProductionCostReport(
        summary,
      ).workbook(currency: 'VND', period: period, parcelFilter: parcel);
      expect(workbook['Documents'].rows, hasLength(2));
      expect(
        (workbook['Currency Filter'].rows[1][0]!.value as TextCellValue).value
            .toString(),
        'VND',
      );
      expect(
        (workbook['Totals'].rows[1][1]!.value as IntCellValue).value,
        2000000,
      );
      final all = await summary.load();
      expect(all.totals.keys, containsAll(['LAK', 'VND', 'USD']));
      expect((await summary.load(currency: 'EUR')).groups, isEmpty);
    },
  );
  test('invalid currency and hidden foreign documents are rejected', () async {
    await expectLater(summary.load(currency: ' '), throwsFormatException);
    expect(store.reads, 0);
    store.items.add(
      fixture.document('foreign', 1, farm: 'other', currency: 'LAK'),
    );
    await expectLater(summary.load(currency: 'VND'), throwsStateError);
  });
  testWidgets(
    'currency survives date changes refresh and export then resets to all',
    (tester) async {
      Excel? exported;
      final day = DateTime(2026, 10, 12);
      await tester.pumpWidget(
        app_fixture.app(
          ProductionCostsScreen(
            service: summary,
            initialParcelId: 'one',
            pickPeriod: (_, _) async => DateTimeRange(start: day, end: day),
            saveReport: (workbook, _) async {
              exported = workbook;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseCurrency(tester, 'currency:VND');
      await tester.tap(find.byKey(const Key('costs-period')));
      await tester.pumpAndSettle();
      expect(find.text('Tổng chi: 2.000.000 VND'), findsOneWidget);
      expect(find.byKey(const Key('costs-total-LAK')), findsNothing);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('costs-currency')),
            )
            .initialValue,
        'currency:VND',
      );
      await tester.tap(find.byKey(const Key('costs-export')));
      await tester.pumpAndSettle();
      expect(exported!['Documents'].rows, hasLength(2));
      expect(
        (exported!['Currency Filter'].rows[1][0]!.value as TextCellValue).value
            .toString(),
        'VND',
      );
      await chooseCurrency(tester, 'all');
      expect(find.byKey(const Key('costs-total-LAK')), findsOneWidget);
      expect(find.byKey(const Key('costs-total-VND')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'currency choices remain available on a narrow screen with empty results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app_fixture.app(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 600),
              textScaler: TextScaler.linear(1.3),
            ),
            child: ProductionCostsScreen(
              service: summary,
              initialParcelId: 'empty',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseCurrency(tester, 'currency:USD');
      expect(find.byKey(const Key('costs-total-USD')), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('costs-currency')),
            )
            .initialValue,
        'currency:USD',
      );
      await chooseCurrency(tester, 'currency:LAK');
      expect(tester.takeException(), isNull);
    },
  );
}
