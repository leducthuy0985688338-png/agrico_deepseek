import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finance_document_details_test.dart' as fixture;

FinanceDocument document(String id, DateTime date, {bool receipt = false}) =>
    FinanceDocument(
      id: id,
      organizationId: 'farm',
      code: id,
      kind: receipt
          ? BusinessDocumentKind.receipt
          : BusinessDocumentKind.payment,
      occurredAt: date,
      amountMinor: 1000000,
      currency: 'LAK',
      category: 'Mua giống',
      description: 'ຂໍ້ມູນ',
    );

class _Store implements FinanceDocumentStore {
  final items = [
    document('before', DateTime(2026, 10, 9, 23, 59)),
    document('start', DateTime(2026, 10, 10, 0, 1)),
    document('end', DateTime.utc(2026, 10, 12, 23, 59)),
    document('after', DateTime(2026, 10, 13)),
    document('receipt', DateTime(2026, 10, 11), receipt: true),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => List.of(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final period = find.byKey(const Key('finance-period'));
  final clear = find.byKey(const Key('finance-clear-period'));
  final start = find.byKey(const Key('finance-document-start'));
  final end = find.byKey(const Key('finance-document-end'));
  final before = find.byKey(const Key('finance-document-before'));
  final after = find.byKey(const Key('finance-document-after'));
  final receipt = find.byKey(const Key('finance-document-receipt'));
  final selected = DateTimeRange(
    start: DateTime(2026, 10, 10),
    end: DateTime(2026, 10, 12),
  );

  testWidgets(
    'period includes both boundary calendar dates and retains complete totals',
    (tester) async {
      final actor = fixture.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(
          FinanceDocumentsScreen(
            service: service,
            pickPeriod: (_, initial) async => selected,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(period);
      await tester.pumpAndSettle();
      expect(start, findsOneWidget);
      expect(end, findsOneWidget);
      expect(before, findsNothing);
      expect(after, findsNothing);
      final listScrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(receipt, 100, scrollable: listScrollable);
      await tester.pumpAndSettle();
      expect(receipt, findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('finance-total-LAK')),
        -100,
        scrollable: listScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('Chi: 4.000.000'), findsOneWidget);
      expect(find.text('Thu: 1.000.000'), findsOneWidget);
      expect(find.text('2026-10-10 – 2026-10-12'), findsOneWidget);
      expect(store.items.length, 5);
    },
  );
  testWidgets(
    'single day combines with kind and query and clear preserves both',
    (tester) async {
      final actor = fixture.actor();
      final service = FinanceDocumentService(
        repository: _Store(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(
          FinanceDocumentsScreen(
            service: service,
            pickPeriod: (_, initial) async =>
                DateTimeRange(start: selected.end, end: selected.end),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-kind-payment')));
      await tester.enterText(find.byKey(const Key('finance-search')), 'ຂໍ້ມູນ');
      await tester.tap(period);
      await tester.pumpAndSettle();
      expect(end, findsOneWidget);
      expect(start, findsNothing);
      expect(receipt, findsNothing);
      await tester.ensureVisible(end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết chứng từ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-details-close')));
      await tester.pumpAndSettle();
      expect(clear, findsOneWidget);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(start, findsOneWidget);
      expect(receipt, findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('finance-search')))
            .controller!
            .text,
        'ຂໍ້ມູນ',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('finance-kind-payment')))
            .selected,
        isTrue,
      );
    },
  );
  testWidgets('cancel leaves existing range and empty results can be cleared', (
    tester,
  ) async {
    final actor = fixture.actor();
    final service = FinanceDocumentService(
      repository: _Store(),
      subject: actor,
      currentSubject: () => actor,
    );
    var calls = 0;
    await tester.pumpWidget(
      fixture.app(
        FinanceDocumentsScreen(
          service: service,
          pickPeriod: (_, initial) async {
            calls++;
            if (calls == 1) {
              return DateTimeRange(start: DateTime(2025), end: DateTime(2025));
            }
            expect(initial!.start, DateTime(2025));
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(period);
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy chứng từ phù hợp.'), findsOneWidget);
    await tester.tap(period);
    await tester.pumpAndSettle();
    expect(find.text('2025-01-01 – 2025-01-01'), findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(start, findsOneWidget);
  });
  testWidgets('revocation while selecting prevents cached data display', (
    tester,
  ) async {
    final initial = fixture.actor();
    var live = initial;
    final service = FinanceDocumentService(
      repository: _Store(),
      subject: initial,
      currentSubject: () => live,
    );
    await tester.pumpWidget(
      fixture.app(
        FinanceDocumentsScreen(
          service: service,
          pickPeriod: (_, range) async {
            live = fixture.actor(view: false);
            return selected;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(period);
    await tester.pumpAndSettle();
    expect(start, findsNothing);
    expect(period, findsNothing);
  });
  testWidgets(
    'period controls and list remain usable with narrow screen and keyboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      final actor = fixture.actor();
      final service = FinanceDocumentService(
        repository: _Store(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: FinanceDocumentsScreen(
                service: service,
                pickPeriod: (_, range) async => selected,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(period);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('finance-search')), 'Mua');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        end,
        100,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(end, findsOneWidget);
      expect(after, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
