import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finance_document_details_test.dart' as fixture;

FinanceDocument saved(String id, String code, String content, String? notes) =>
    FinanceDocument(
      id: id,
      organizationId: 'farm',
      code: code,
      kind: BusinessDocumentKind.payment,
      occurredAt: DateTime(2026, 10, 12),
      amountMinor: 1000000,
      currency: 'LAK',
      category: content,
      description: notes,
    );

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [
    saved('one', 'CHI-202610-001', 'Mua vật tư', 'ຂໍ້ມູນ'),
    saved('two', 'CHI-202610-002', 'Trả công', null),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => List.of(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final search = find.byKey(const Key('finance-search'));
  final one = find.byKey(const Key('finance-document-one'));
  final two = find.byKey(const Key('finance-document-two'));
  testWidgets(
    'search matches code, content and Unicode notes without changing totals',
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
      for (final query in [' chi-202610-001 ', 'MUA VẬT TƯ', 'ຂໍ້ມູນ']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(one, findsOneWidget);
        expect(two, findsNothing);
        expect(find.text('Chi: 2.000.000'), findsOneWidget);
      }
      expect(store.items.length, 2);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(one);
      await tester.tap(one);
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết chứng từ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-details-close')));
      await tester.pumpAndSettle();
      expect(two, findsNothing);
    },
  );
  testWidgets(
    'no matches keep search accessible and clear restores all documents',
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
      await tester.enterText(search, 'missing');
      await tester.pumpAndSettle();
      expect(one, findsNothing);
      expect(two, findsNothing);
      expect(find.text('Không tìm thấy chứng từ phù hợp.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-search-clear')));
      await tester.pumpAndSettle();
      expect(one, findsOneWidget);
      expect(two, findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      await tester.enterText(search, '   ');
      await tester.pumpAndSettle();
      expect(one, findsOneWidget);
      expect(two, findsOneWidget);
    },
  );
  testWidgets('revoked access hides cached data when searching', (
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
      fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    live = fixture.actor(view: false);
    await tester.enterText(search, 'CHI');
    await tester.pumpAndSettle();
    expect(one, findsNothing);
    expect(two, findsNothing);
    expect(search, findsNothing);
  });
  testWidgets('search remains usable on a narrow screen with keyboard', (
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
      fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(search, 'Trả công');
    await tester.pumpAndSettle();
    expect(one, findsNothing);
    await tester.scrollUntilVisible(
      two,
      100,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(two, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
