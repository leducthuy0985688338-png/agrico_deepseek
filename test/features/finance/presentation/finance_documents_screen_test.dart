import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:excel/excel.dart';
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
  testWidgets('view-only finance hides create and export actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: FinanceDocumentsScreen(
          service: _service(
            _MemoryFinanceStore(),
            permissions: const {PermissionCodes.financeView},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-add')), findsNothing);
    expect(find.byKey(const Key('finance-export-v2')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved payment shows its generated code after reopening', (
    tester,
  ) async {
    final repository = _MemoryFinanceStore();
    Excel? exported;
    String? exportedName;

    Widget app() => MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: FinanceDocumentsScreen(
        service: _service(repository),
        saveReport: (workbook, fileName) async {
          exported = workbook;
          exportedName = fileName;
        },
      ),
    );

    await tester.pumpWidget(app());
    await tester
        .pump(); // Let the repository future complete and schedule its frame.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finance-add')));
    await tester.pumpAndSettle();
    expect(
      const AppLocalizations(Locale('vi')).text('finance.currency.lak'),
      'Kíp Lào (LAK)',
    );
    expect(
      const AppLocalizations(Locale('lo')).text('finance.summary'),
      'ສະຫຼຸບໃບບັນທຶກ',
    );
    expect(
      const AppLocalizations(Locale('en')).text('finance.balance'),
      'Receipts less payments',
    );
    await tester.enterText(
      find.byKey(const Key('finance-category')),
      'ຂາຍມັນຕົ້ນ',
    );
    await tester.enterText(find.byKey(const Key('finance-amount')), '25000');
    await tester.tap(find.byKey(const Key('finance-save')));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.textContaining('CHI-'), findsWidgets);
    expect(find.byKey(const Key('finance-total-LAK')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('finance-total-LAK')),
        matching: find.textContaining('25.000'),
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const Key('finance-export-v2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finance-export-all')));
    await tester.pumpAndSettle();
    expect(exportedName, startsWith('BaoCaoChungTuV2-'));
    expect(exportedName, endsWith('.xlsx'));
    final firstExportName = exportedName;
    await tester.tap(find.byKey(const Key('finance-export-v2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finance-export-all')));
    await tester.pumpAndSettle();
    expect(exportedName, isNot(firstExportName));
    expect(exported!['Finance V2'].rows, hasLength(2));
    expect(exported!['Totals V2'].rows, hasLength(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('CHI-'), findsWidgets);
    expect(
      (await repository.listByOrganization('farm-a')).single.category,
      'ຂາຍມັນຕົ້ນ',
    );
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
