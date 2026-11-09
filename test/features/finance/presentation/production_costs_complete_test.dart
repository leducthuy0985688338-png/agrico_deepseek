import 'dart:async';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_period.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_report.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/production_cost_summary_test.dart' as fixture;
import 'finance_document_details_test.dart' as app_fixture;

FinanceDocument payment(
  String id, {
  int amount = 1000000,
  String currency = 'LAK',
  String? parcel = 'one',
}) => FinanceDocument(
  id: id,
  organizationId: 'farm',
  code: 'CHI-$id',
  kind: BusinessDocumentKind.payment,
  occurredAt: DateTime(2026, 10, 12, 23, 59),
  amountMinor: amount,
  currency: currency,
  category: 'Giống ຖົ່ວ $id',
  parcelId: parcel,
  description: 'Ghi chú ຂໍ້ມູນ $id',
);

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [
    payment('one'),
    payment('two', currency: 'VND', parcel: 'two'),
  ];
  int reads = 0;
  Future<List<FinanceDocument>>? next;
  @override
  Future<List<FinanceDocument>> listByOrganization(String organizationId) {
    reads++;
    final result = next;
    next = null;
    return result ?? Future.value(List.of(items));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    100,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('costs-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  test(
    'persisted SQLite payments reconcile with overview and currency totals',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await SqliteFinanceDocumentRepository.createSchema(db);
        final repository = SqliteFinanceDocumentRepository(db);
        for (final doc in [
          payment('one'),
          payment('two', currency: 'VND'),
          payment('foreign'),
        ]) {
          await repository.create(
            id: doc.id,
            organizationId: doc.id == 'foreign' ? 'other' : 'farm',
            kind: doc.kind,
            occurredAt: doc.occurredAt,
            amountMinor: doc.amountMinor,
            currency: doc.currency,
            category: doc.category,
            parcelId: doc.parcelId,
            description: doc.description,
          );
        }
        await repository.create(
          id: 'receipt',
          organizationId: 'farm',
          kind: BusinessDocumentKind.receipt,
          occurredAt: DateTime(2026, 10, 12),
          amountMinor: 7000000,
          currency: 'LAK',
          category: 'Thu',
        );
        final actor = fixture.actor();
        final persisted = ProductionCostSummary(
          FinanceDocumentService(
            repository: SqliteFinanceDocumentRepository(db),
            subject: actor,
            currentSubject: () => actor,
          ),
        );
        final day = DateTime(2026, 10, 12);
        final book = await ProductionCostReport(persisted).workbook(
          period: ProductionCostPeriod(from: day, to: day),
          query: 'ຂໍ້ມູນ',
        );
        expect(book['Documents'].rows, hasLength(3));
        expect(book['Totals'].rows, hasLength(3));
        expect((book['Overview'].rows[0][1]!.value as IntCellValue).value, 2);
        expect((await persisted.load(currency: 'LAK')).totals, {
          'LAK': 1000000,
        });
      } finally {
        await db.close();
      }
    },
  );
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
  test(
    'payment count agrees with integer totals and exported overview',
    () async {
      store.items.add(payment('large', amount: 9007199254740993));
      final report = await summary.load();
      expect(report.documentCount, 3);
      expect(report.totals['LAK'], 9007199255740993);
      final book = await ProductionCostReport(summary).workbook(query: 'two');
      expect((book['Overview'].rows[0][1]!.value as IntCellValue).value, 1);
      expect(book['Documents'].rows, hasLength(2));
      expect((book['Totals'].rows[1][1]!.value as IntCellValue).value, 1000000);
    },
  );
  test(
    'duplicate and invalid saved payments cannot silently distort totals',
    () async {
      store.items = [payment('same'), payment('same')];
      await expectLater(summary.load(), throwsStateError);
      for (final invalid in [
        payment('negative', amount: -1),
        payment('zero', amount: 0),
        payment('currency', currency: ' '),
        payment('parcel', parcel: ' '),
      ]) {
        store.items = [payment('match'), invalid];
        await expectLater(summary.load(query: 'match'), throwsStateError);
      }
    },
  );
  testWidgets(
    'landscape keyboard and large text keep every control reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(568, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app_fixture.app(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(568, 320),
              viewInsets: EdgeInsets.only(bottom: 140),
              textScaler: TextScaler.linear(1.5),
            ),
            child: ProductionCostsScreen(service: summary),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('costs-search')), 'two');
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('costs-period')));
      expect(
        find.byKey(const Key('costs-period')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late date picker result cannot restore filters after clear', (
    tester,
  ) async {
    final picked = Completer<DateTimeRange?>();
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          initialParcelId: 'one',
          pickPeriod: (_, _) => picked.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('costs-period')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('costs-clear-filters')));
    await tester.pumpAndSettle();
    final before = store.reads;
    picked.complete(
      DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 12)),
    );
    await tester.pumpAndSettle();
    expect(store.reads, before);
    expect(find.byKey(const Key('costs-clear-period')), findsNothing);
    expect(find.byKey(const Key('costs-clear-filters')), findsNothing);
  });
  testWidgets('date picker rechecks report grant before applying a result', (
    tester,
  ) async {
    final picked = Completer<DateTimeRange?>();
    await tester.pumpWidget(
      app_fixture.app(
        ProductionCostsScreen(
          service: summary,
          pickPeriod: (_, _) => picked.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('costs-period')));
    await tester.pump();
    live = fixture.actor(report: false);
    picked.complete(
      DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 12)),
    );
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(find.byKey(const Key('costs-search')), findsNothing);
    expect(find.byKey(const Key('costs-total-LAK')), findsNothing);
  });
  testWidgets('parcel callback obtained earlier cannot read after revocation', (
    tester,
  ) async {
    await tester.pumpWidget(
      app_fixture.app(ProductionCostsScreen(service: summary)),
    );
    await tester.pumpAndSettle();
    final callback = tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('costs-parcel')),
        )
        .onChanged!;
    live = fixture.actor(report: false);
    callback('parcel:one');
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('out of order search results never replace newer totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      app_fixture.app(ProductionCostsScreen(service: summary)),
    );
    await tester.pumpAndSettle();
    final pending = Completer<List<FinanceDocument>>();
    store.next = pending.future;
    await tester.enterText(find.byKey(const Key('costs-search')), 'one');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('costs-search')), 'two');
    await tester.pumpAndSettle();
    pending.complete([payment('one', amount: 9000000)]);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('costs-total-VND')));
    expect(find.text('Tổng chi: 1.000.000 VND'), findsOneWidget);
    expect(find.byKey(const Key('costs-total-LAK')), findsNothing);
  });
  testWidgets(
    'export freezes controls and can recover after file writer failure',
    (tester) async {
      final saved = Completer<void>();
      var writes = 0;
      await tester.pumpWidget(
        app_fixture.app(
          ProductionCostsScreen(
            service: summary,
            initialParcelId: 'one',
            saveReport: (_, _) {
              writes++;
              return writes == 1 ? saved.future : Future.value();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costs-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costs-export-all')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<TextField>(find.byKey(const Key('costs-search'))).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('costs-clear-filters')))
            .onPressed,
        isNull,
      );
      saved.completeError(StateError('Writer failed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costs-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costs-export-filtered')));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
