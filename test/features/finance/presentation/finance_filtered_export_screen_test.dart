import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/finance_parcel_link_test.dart' as actor_fixture;
import '../application/finance_filtered_export_test.dart' as documents;
import 'finance_document_details_test.dart' as app_fixture;

class _Store implements FinanceDocumentStore {
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => [
    documents.document('match'),
    documents.document('other', parcel: 'two'),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'export menu offers filtered and all without changing display filters',
    (tester) async {
      final actor = actor_fixture.actor();
      final service = FinanceDocumentService(
        repository: _Store(),
        subject: actor,
        currentSubject: () => actor,
      );
      final exported = <Excel>[];
      await tester.pumpWidget(
        app_fixture.app(
          FinanceDocumentsScreen(
            service: service,
            saveReport: (workbook, fileName) async {
              exported.add(workbook);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('finance-search')), 'match');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-export-v2')));
      await tester.pumpAndSettle();
      expect(exported, isEmpty);
      await tester.tap(find.byKey(const Key('finance-export-filtered')));
      await tester.pumpAndSettle();
      expect(exported.single['Finance V2'].rows, hasLength(2));
      expect(
        (exported.single['Finance V2'].rows[1][0]!.value as TextCellValue).value
            .toString(),
        'match',
      );
      await tester.tap(find.byKey(const Key('finance-export-v2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-export-all')));
      await tester.pumpAndSettle();
      expect(exported.last['Finance V2'].rows, hasLength(3));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('finance-search')))
            .controller!
            .text,
        'match',
      );
    },
  );
}
