import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saved payment shows its generated code after reopening', (tester) async {
    final repository = _MemoryFinanceStore();

    Widget app() => MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: FinanceDocumentsScreen(
        repository: repository,
        organizationId: 'farm-a',
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Chưa có dữ liệu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finance-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('finance-category')), 'ຂາຍມັນຕົ້ນ');
    await tester.enterText(find.byKey(const Key('finance-amount')), '25000');
    await tester.tap(find.byKey(const Key('finance-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('CHI-'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('CHI-'), findsWidgets);
    expect((await repository.listByOrganization('farm-a')).single.category, 'ຂາຍມັນຕົ້ນ');
    await tester.pumpWidget(const SizedBox());
  });
}

class _MemoryFinanceStore implements FinanceDocumentStore {
  final documents = <FinanceDocument>[];

  @override
  Future<FinanceDocument> create({
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
  }) async {
    final document = FinanceDocument(
      id: id, organizationId: organizationId,
      code: BusinessReferenceCode.forDate(
        kind: kind, date: occurredAt, sequence: documents.length + 1,
      ).toString(),
      kind: kind, occurredAt: occurredAt, amountMinor: amountMinor,
      currency: currency, category: category,
      parcelId: parcelId, description: description,
    );
    documents.add(document);
    return document;
  }

  @override
  Future<List<FinanceDocument>> listByOrganization(String organizationId) async =>
      documents.where((doc) => doc.organizationId == organizationId).toList();
}
