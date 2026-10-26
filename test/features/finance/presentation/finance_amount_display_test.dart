import 'package:flutter_localizations/flutter_localizations.dart';
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
    PermissionCodes.cashView,
    PermissionCodes.cashRecord,
    PermissionCodes.dataExport,
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
  testWidgets('document amounts and signed totals use dot grouping', (
    tester,
  ) async {
    final repository = _MemoryFinanceStore();
    for (final entry in [
      (BusinessDocumentKind.payment, 1000000),
      (BusinessDocumentKind.receipt, 2000000),
      (BusinessDocumentKind.payment, 3000000),
    ]) {
      await repository.create(
        id: '${repository.documents.length}',
        organizationId: 'farm-a',
        kind: entry.$1,
        occurredAt: DateTime(2026),
        amountMinor: entry.$2,
        currency: 'LAK',
        category: 'Test',
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FinanceDocumentsScreen(service: _service(repository)),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    const l10n = AppLocalizations(Locale('vi'));
    expect(
      find.text('${l10n.text('finance.receipt')}: 2.000.000'),
      findsOneWidget,
    );
    expect(
      find.text('${l10n.text('finance.payment')}: 4.000.000'),
      findsOneWidget,
    );
    expect(
      find.text('${l10n.text('finance.balance')}: -2.000.000'),
      findsOneWidget,
    );
    for (final amount in ['1.000.000', '2.000.000', '3.000.000']) {
      expect(find.textContaining('$amount '), findsOneWidget);
    }
    expect(repository.documents.map((doc) => doc.amountMinor), [
      1000000,
      2000000,
      3000000,
    ]);
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
