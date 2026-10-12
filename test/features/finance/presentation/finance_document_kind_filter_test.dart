import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finance_document_details_test.dart' as fixture;

class _Store implements FinanceDocumentStore {
  final items = [
    FinanceDocument(
      id: 'receipt',
      organizationId: 'farm',
      code: 'THU-001',
      kind: BusinessDocumentKind.receipt,
      occurredAt: DateTime(2026, 10, 12),
      amountMinor: 3000000,
      currency: 'LAK',
      category: 'Bán lạc',
    ),
    FinanceDocument(
      id: 'payment',
      organizationId: 'farm',
      code: 'CHI-001',
      kind: BusinessDocumentKind.payment,
      occurredAt: DateTime(2026, 10, 12),
      amountMinor: 1000000,
      currency: 'LAK',
      category: 'Mua giống',
      description: 'ຂໍ້ມູນ',
    ),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => List.of(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final receipt = find.byKey(const Key('finance-document-receipt'));
  final payment = find.byKey(const Key('finance-document-payment'));
  final all = find.byKey(const Key('finance-kind-all'));
  final receipts = find.byKey(const Key('finance-kind-receipt'));
  final payments = find.byKey(const Key('finance-kind-payment'));
  final search = find.byKey(const Key('finance-search'));
  testWidgets(
    'all receipt and payment selections keep complete currency totals',
    (tester) async {
      final actor = fixture.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(receipt, findsOneWidget);
      expect(payment, findsOneWidget);
      await tester.tap(receipts);
      await tester.pumpAndSettle();
      expect(receipt, findsOneWidget);
      expect(payment, findsNothing);
      expect(find.text('Thu: 3.000.000'), findsOneWidget);
      expect(find.text('Chi: 1.000.000'), findsOneWidget);
      await tester.tap(payments);
      await tester.pumpAndSettle();
      expect(receipt, findsNothing);
      expect(payment, findsOneWidget);
      await tester.ensureVisible(payment);
      await tester.tap(payment);
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết chứng từ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-details-close')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(payments).selected, isTrue);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(receipt, findsOneWidget);
      expect(payment, findsOneWidget);
      expect(store.items.length, 2);
    },
  );
  testWidgets(
    'kind and search combine and clearing search retains selected kind',
    (tester) async {
      final actor = fixture.actor();
      final service = FinanceDocumentService(
        repository: _Store(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await tester.tap(payments);
      await tester.enterText(search, 'ຂໍ້ມູນ');
      await tester.pumpAndSettle();
      expect(payment, findsOneWidget);
      expect(receipt, findsNothing);
      await tester.tap(receipts);
      await tester.pumpAndSettle();
      expect(payment, findsNothing);
      expect(receipt, findsNothing);
      expect(find.text('Không tìm thấy chứng từ phù hợp.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-search-clear')));
      await tester.pumpAndSettle();
      expect(receipt, findsOneWidget);
      expect(payment, findsNothing);
      expect(tester.widget<ChoiceChip>(receipts).selected, isTrue);
    },
  );
  testWidgets('filter rebuild respects revoked access', (tester) async {
    final initial = fixture.actor();
    var live = initial;
    final service = FinanceDocumentService(
      repository: _Store(),
      subject: initial,
      currentSubject: () => live,
    );
    await tester.pumpWidget(
      fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    live = fixture.actor(view: false);
    await tester.tap(receipts);
    await tester.pumpAndSettle();
    expect(receipt, findsNothing);
    expect(payment, findsNothing);
    expect(receipts, findsNothing);
  });
  testWidgets('filters wrap on narrow screen with enlarged text and keyboard', (
    tester,
  ) async {
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
            child: FinanceDocumentsScreen(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(payments);
    await tester.enterText(search, 'MUA');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      payment,
      100,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(payment, findsOneWidget);
    expect(receipt, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
