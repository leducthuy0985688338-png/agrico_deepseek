import 'dart:async';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/production_cost_summary_test.dart' as fixture;
import 'finance_document_details_test.dart' as app_fixture;
import 'production_cost_currency_filter_test.dart' as currency_ui;

class _Store implements FinanceDocumentStore {
  int reads = 0;
  Completer<List<FinanceDocument>>? nextRead;
  final items = [
    fixture.document(
      'one',
      1000000,
      parcelId: 'one',
      date: DateTime(2026, 10, 12),
    ),
    fixture.document(
      'two',
      2000000,
      parcelId: 'two',
      currency: 'VND',
      date: DateTime(2026, 9, 1),
    ),
    fixture.document('general', 3000000, date: DateTime(2026, 10, 12)),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    final pending = nextRead;
    nextRead = null;
    if (pending != null) {
      return pending.future;
    }
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String? value(WidgetTester tester, String key) => tester
    .widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(DropdownButton<String>),
      ),
    )
    .value;
void main() {
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late ProductionCostSummary summary;
  setUp(() {
    store = _Store();
    initial = fixture.actor();
    live = initial;
    summary = ProductionCostSummary(
      FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => live,
      ),
    );
  });
  testWidgets('clear resets parcel date currency and exported scope together', (
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
    final before = store.reads;
    await tester.tap(find.byKey(const Key('costs-clear-filters')));
    await tester.pumpAndSettle();
    expect(store.reads, before + 1);
    expect(value(tester, 'costs-parcel'), 'all');
    expect(value(tester, 'costs-currency'), 'all');
    expect(find.byKey(const Key('costs-clear-period')), findsNothing);
    expect(find.byKey(const Key('costs-clear-filters')), findsNothing);
    expect(find.text('Tổng chi: 4.000.000 LAK'), findsOneWidget);
    expect(find.text('Tổng chi: 2.000.000 VND'), findsOneWidget);
    await tester.tap(find.byKey(const Key('costs-export')));
    await tester.pumpAndSettle();
    expect(exported!['Documents'].rows, hasLength(4));
    expect(
      (exported!['Currency Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'All',
    );
    expect(
      (exported!['Parcel Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'all',
    );
    expect(
      (exported!['Period'].rows[1][0]!.value as TextCellValue).value.toString(),
      'All dates',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'clear is available for an empty initial parcel on a narrow screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app_fixture.app(
          ProductionCostsScreen(service: summary, initialParcelId: 'empty'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costs-clear-filters')));
      await tester.pumpAndSettle();
      expect(value(tester, 'costs-parcel'), 'all');
      expect(find.byKey(const Key('costs-clear-filters')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late refresh result cannot restore filters after clearing', (
    tester,
  ) async {
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(service: summary, initialParcelId: 'one'),
      ),
    );
    await tester.pumpAndSettle();
    final pending = Completer<List<FinanceDocument>>();
    store.nextRead = pending;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.tap(find.byKey(const Key('costs-clear-filters')));
    await tester.pumpAndSettle();
    pending.complete(List.of(store.items));
    await tester.pumpAndSettle();
    expect(value(tester, 'costs-parcel'), 'all');
    expect(find.byKey(const Key('costs-clear-filters')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('revoked access blocks clear callback without another read', (
    tester,
  ) async {
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(service: summary, initialParcelId: 'one'),
      ),
    );
    await tester.pumpAndSettle();
    final before = store.reads;
    live = fixture.actor(report: false);
    await tester.tap(find.byKey(const Key('costs-clear-filters')));
    await tester.pumpAndSettle();
    expect(store.reads, before);
    expect(tester.takeException(), isNull);
  });
}
