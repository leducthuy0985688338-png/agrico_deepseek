import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
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
import 'production_cost_currency_filter_test.dart' as currency_ui;

FinanceDocument document(
  String id, {
  String currency = 'LAK',
  String? parcel = 'one',
  int day = 12,
  bool receipt = false,
  String farm = 'farm',
}) => FinanceDocument(
  id: id,
  organizationId: farm,
  code: 'CHI-$id',
  kind: receipt ? BusinessDocumentKind.receipt : BusinessDocumentKind.payment,
  occurredAt: DateTime(2026, 10, day),
  amountMinor: 1000000,
  currency: currency,
  parcelId: parcel,
  category: 'Mua giống $id',
  description: 'ຂໍ້ມູນ $id',
);

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [
    document('match'),
    document('vnd', currency: 'VND'),
    document('other', parcel: 'two'),
    document('old', day: 1),
    document('receipt', receipt: true),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => List.of(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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
    'search matches code category notes with trim case folding and intersects filters',
    () async {
      for (final query in [' chi-MATCH ', 'GIỐNG MATCH', 'ຂໍ້ມູນ match']) {
        final snapshot = await summary.load(query: query);
        expect(snapshot.groups.single.documents.single.id, 'match');
        expect(snapshot.totals, {'LAK': 1000000});
      }
      final day = DateTime(2026, 10, 12);
      final book = await ProductionCostReport(summary).workbook(
        query: ' ຂໍ້ມູນ ',
        currency: 'LAK',
        parcelFilter: const ProductionCostParcelFilter.parcel('one'),
        period: ProductionCostPeriod(from: day, to: day),
      );
      expect(book['Documents'].rows, hasLength(2));
      expect(
        (book['Search Filter'].rows[1][0]!.value as TextCellValue).value
            .toString(),
        'ຂໍ້ມູນ',
      );
      expect((book['Totals'].rows[1][1]!.value as IntCellValue).value, 1000000);
      expect(
        (await summary.load(query: '   ')).groups.expand((g) => g.documents),
        hasLength(4),
      );
      expect((await summary.load(query: 'missing')).totals, isEmpty);
    },
  );
  test('search cannot hide foreign documents from scope validation', () async {
    store.items.add(document('foreign', farm: 'other'));
    await expectLater(summary.load(query: 'match'), throwsStateError);
  });
  testWidgets('search refresh export and clear use the same scope', (
    tester,
  ) async {
    Excel? exported;
    final day = DateTime(2026, 10, 12);
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          initialParcelId: 'one',
          pickPeriod: (_, _) async => DateTimeRange(start: day, end: day),
          saveReport: (book, _) async {
            exported = book;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await currency_ui.chooseCurrency(tester, 'currency:LAK');
    await tester.tap(find.byKey(const Key('costs-period')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('costs-search')), 'match');
    await tester.pumpAndSettle();
    expect(find.text('Tổng chi: 1.000.000 LAK'), findsOneWidget);
    await tester
        .widget<RefreshIndicator>(find.byKey(const Key('costs-refresh')))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('costs-search')))
          .controller!
          .text,
      'match',
    );
    await tester.tap(find.byKey(const Key('costs-export')));
    await tester.pumpAndSettle();
    expect(exported!['Documents'].rows, hasLength(2));
    expect(
      (exported!['Search Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'match',
    );
    await tester.tap(find.byKey(const Key('costs-clear-search')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('costs-parcel')),
          )
          .initialValue,
      'parcel:one',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('costs-currency')),
          )
          .initialValue,
      'currency:LAK',
    );
    expect(find.byKey(const Key('costs-clear-period')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('costs-search')), 'missing');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('costs-clear-filters')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('costs-search')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('costs-clear-filters')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search works on narrow screen with enlarged text and keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app_fixture.app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 600),
            viewInsets: EdgeInsets.only(bottom: 220),
            textScaler: TextScaler.linear(1.3),
          ),
          child: ProductionCostsScreen(service: summary),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('costs-search')),
      'ຂໍ້ມູນ match',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('costs-search')))
          .controller!
          .text,
      'ຂໍ້ມູນ match',
    );
    expect(find.byKey(const Key('costs-clear-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
