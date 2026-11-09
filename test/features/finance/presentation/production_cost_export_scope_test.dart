import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/production_cost_summary_test.dart' as actors;
import 'finance_document_details_test.dart' as app_fixture;
import 'production_cost_search_test.dart' as documents;
import 'production_cost_currency_filter_test.dart' as currency_ui;

class _Store implements FinanceDocumentStore {
  int reads = 0;
  void Function()? onRead;
  final items = [
    documents.document('match'),
    documents.document('vnd', currency: 'VND'),
    documents.document('other', parcel: 'two'),
    documents.document('old', day: 1),
    documents.document('receipt', receipt: true),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    onRead?.call();
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> chooseExport(WidgetTester tester, bool filtered) async {
  await tester.tap(find.byKey(const Key('costs-export')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(Key(filtered ? 'costs-export-filtered' : 'costs-export-all')),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late ProductionCostSummary summary;
  setUp(() {
    store = _Store();
    initial = actors.actor();
    live = initial;
    summary = ProductionCostSummary(
      FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => live,
      ),
    );
  });
  testWidgets('filtered and all exports preserve all four display filters', (
    tester,
  ) async {
    final books = <Excel>[];
    final names = <String>[];
    final day = DateTime(2026, 10, 12);
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          initialParcelId: 'one',
          pickPeriod: (_, _) async => DateTimeRange(start: day, end: day),
          saveReport: (book, name) async {
            books.add(book);
            names.add(name);
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
    await chooseExport(tester, true);
    expect(books.single['Documents'].rows, hasLength(2));
    expect(
      (books.single['Search Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'match',
    );
    await chooseExport(tester, false);
    expect(books.last['Documents'].rows, hasLength(5));
    expect(
      (books.last['Currency Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'All',
    );
    expect(
      (books.last['Parcel Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'all',
    );
    expect(
      (books.last['Period'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      'All dates',
    );
    expect(
      (books.last['Search Filter'].rows[1][0]!.value as TextCellValue).value
          .toString(),
      '',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('costs-search')))
          .controller!
          .text,
      'match',
    );
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
    expect(find.text('Tổng chi: 1.000.000 LAK'), findsOneWidget);
    expect(names.toSet(), hasLength(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelled export menu performs no persisted read or write', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          saveReport: (_, _) async {
            writes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = store.reads;
    await tester.tap(find.byKey(const Key('costs-export')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 500));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(store.reads, before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('permission revoked while menu is open prevents export', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          saveReport: (_, _) async {
            writes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = store.reads;
    await tester.tap(find.byKey(const Key('costs-export')));
    await tester.pumpAndSettle();
    live = actors.actor(report: false);
    await tester.tap(find.byKey(const Key('costs-export-all')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(store.reads, before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('revocation during all export prevents file writer', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          saveReport: (_, _) async {
            writes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    store.onRead = () {
      live = actors.actor(report: false);
    };
    await chooseExport(tester, false);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
}
