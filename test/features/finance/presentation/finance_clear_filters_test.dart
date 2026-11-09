import 'dart:async';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finance_document_details_test.dart' as app_fixture;
import 'finance_filtered_totals_test.dart' as fixture;
import 'finance_document_parcel_filter_test.dart' as parcel_ui;

class _Store implements FinanceDocumentStore {
  int reads = 0;
  Future<void>? gate;
  final items = [
    fixture.document('one'),
    fixture.document('receipt', receipt: true),
    fixture.document('general', parcel: null),
    fixture.document('old', day: 9),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    if (gate != null) {
      await gate;
    }
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> applyFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('finance-kind-payment')));
  await tester.tap(find.byKey(const Key('finance-period')));
  await tester.pumpAndSettle();
  await parcel_ui.choose(tester, 'parcel:one');
  await tester.enterText(find.byKey(const Key('finance-search')), 'ຂໍ້ມູນ');
  await tester.pumpAndSettle();
}

void expectDefaults(WidgetTester tester) {
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('finance-search')))
        .controller!
        .text,
    isEmpty,
  );
  expect(
    tester
        .widget<ChoiceChip>(find.byKey(const Key('finance-kind-all')))
        .selected,
    isTrue,
  );
  expect(find.byKey(const Key('finance-clear-period')), findsNothing);
  expect(find.byKey(const Key('finance-clear-filters')), findsNothing);
  final selector = find.byKey(const Key('finance-parcel-filter'));
  final dropdown = tester.widget<DropdownButton<String>>(
    find.descendant(
      of: selector,
      matching: find.byType(DropdownButton<String>),
    ),
  );
  expect(dropdown.value, 'all');
}

void main() {
  final reset = find.byKey(const Key('finance-clear-filters'));
  testWidgets(
    'reset clears all four filters without another read or changes to documents',
    (tester) async {
      final actor = fixture.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      );
      final date = DateTime(2026, 10, 12);
      await tester.pumpWidget(
        app_fixture.app(
          FinanceDocumentsScreen(
            service: service,
            pickPeriod: (_, initial) async =>
                DateTimeRange(start: date, end: date),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reset, findsNothing);
      await applyFilters(tester);
      expect(find.byKey(const Key('finance-document-general')), findsNothing);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expectDefaults(tester);
      for (final id in ['one', 'receipt', 'general', 'old']) {
        final row = find.byKey(Key('finance-document-$id'));
        await tester.scrollUntilVisible(
          row,
          100,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(row, findsOneWidget);
      }
      expect(store.reads, 1);
      expect(store.items.length, 4);
    },
  );
  testWidgets(
    'reset recovers empty search and whitespace with no storage reads',
    (tester) async {
      final actor = fixture.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        app_fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      for (final query in ['missing', '   ']) {
        await tester.enterText(find.byKey(const Key('finance-search')), query);
        await tester.pumpAndSettle();
        expect(reset, findsOneWidget);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expectDefaults(tester);
      }
      expect(store.reads, 1);
    },
  );
  testWidgets('reset remains effective when a pending refresh completes', (
    tester,
  ) async {
    final actor = fixture.actor();
    final store = _Store();
    final service = FinanceDocumentService(
      repository: store,
      subject: actor,
      currentSubject: () => actor,
    );
    await tester.pumpWidget(
      app_fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('finance-search')), 'missing');
    await tester.pumpAndSettle();
    final pending = Completer<void>();
    store.gate = pending.future;
    final loading = tester
        .widget<RefreshIndicator>(find.byKey(const Key('finance-refresh')))
        .onRefresh();
    await tester.pump();
    await tester.tap(reset);
    await tester.pump();
    pending.complete();
    await loading;
    await tester.pumpAndSettle();
    expectDefaults(tester);
    expect(store.reads, 2);
  });
  testWidgets('revoked view blocks reset from showing cached documents', (
    tester,
  ) async {
    final initial = fixture.actor();
    AuthorizationSubject? live = initial;
    final store = _Store();
    final service = FinanceDocumentService(
      repository: store,
      subject: initial,
      currentSubject: () => live,
    );
    await tester.pumpWidget(
      app_fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('finance-search')), 'missing');
    await tester.pumpAndSettle();
    live = null;
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-document-one')), findsNothing);
    expect(reset, findsNothing);
    expect(store.reads, 1);
  });
}
