import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceDocumentService _service(
  FinanceDocumentStore repository, {
  Set<String> permissions = const {
    PermissionCodes.financeView,
    PermissionCodes.financeCreate,
    PermissionCodes.reportFinance,
  },
}) {
  final subject = AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: 'farm-a',
    permissionCodes: permissions,
    dataScopes: const {DataScope.allFarm},
    validUntil: DateTime.now().add(const Duration(hours: 1)),
  );
  return FinanceDocumentService(
    repository: repository,
    subject: subject,
    currentSubject: () => subject,
  );
}

void main() {
  testWidgets('formatted amount saves the exact integer value', (tester) async {
    final repository = _MemoryFinanceStore();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: FinanceDocumentsScreen(service: _service(repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finance-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('finance-category')), 'Test');
    await tester.enterText(find.byKey(const Key('finance-amount')), '1000000');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('finance-amount')))
          .controller!
          .text,
      '1.000.000',
    );
    await tester.tap(find.byKey(const Key('finance-save')));
    await tester.pumpAndSettle();
    expect(repository.documents.single.amountMinor, 1000000);
    expect(tester.takeException(), isNull);
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
      id: id,
      organizationId: organizationId,
      code: BusinessReferenceCode.forDate(
        kind: kind,
        date: occurredAt,
        sequence: documents.length + 1,
      ).toString(),
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      parcelId: parcelId,
      description: description,
    );
    documents.add(document);
    return document;
  }

  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async =>
      documents.where((doc) => doc.organizationId == organizationId).toList();
}
