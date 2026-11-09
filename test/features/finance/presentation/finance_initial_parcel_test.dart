import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/finance_parcel_link_test.dart' as actors;
import 'finance_document_details_test.dart' as app_fixture;
import 'finance_document_parcel_filter_test.dart' as parcel_fixture;

class _Store implements FinanceDocumentStore {
  var reads = 0;
  final items = [
    parcel_fixture.document('one', 'one'),
    parcel_fixture.document('two', 'two'),
    parcel_fixture.document('general', null),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String? selectedParcel(WidgetTester tester) => tester
    .widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('finance-parcel-filter')),
        matching: find.byType(DropdownButton<String>),
      ),
    )
    .value;

void main() {
  testWidgets(
    'initial parcel applies to exports and survives refresh until cleared',
    (tester) async {
      final actor = actors.actor();
      final store = _Store();
      final exports = <Excel>[];
      await tester.pumpWidget(
        app_fixture.app(
          FinanceDocumentsScreen(
            service: FinanceDocumentService(
              repository: store,
              subject: actor,
              currentSubject: () => actor,
            ),
            initialParcelId: 'one',
            saveReport: (workbook, name) async {
              exports.add(workbook);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(selectedParcel(tester), 'parcel:one');
      expect(find.byKey(const Key('finance-document-two')), findsNothing);
      expect(find.byKey(const Key('finance-document-general')), findsNothing);
      await tester.tap(find.byKey(const Key('finance-export-v2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-export-filtered')));
      await tester.pumpAndSettle();
      expect(exports.single['Finance V2'].rows, hasLength(2));
      expect(
        (exports.single['Finance V2'].rows[1][0]!.value as TextCellValue).value
            .toString(),
        'one',
      );
      await tester
          .widget<RefreshIndicator>(find.byKey(const Key('finance-refresh')))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(selectedParcel(tester), 'parcel:one');
      await tester.tap(find.byKey(const Key('finance-clear-filters')));
      await tester.pumpAndSettle();
      expect(selectedParcel(tester), 'all');
      expect(find.byKey(const Key('finance-clear-filters')), findsNothing);
    },
  );

  testWidgets(
    'initial parcel without documents remains selectable and can be changed',
    (tester) async {
      final actor = actors.actor();
      await tester.pumpWidget(
        app_fixture.app(
          FinanceDocumentsScreen(
            service: FinanceDocumentService(
              repository: _Store(),
              subject: actor,
              currentSubject: () => actor,
            ),
            initialParcelId: 'empty',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(selectedParcel(tester), 'parcel:empty');
      expect(find.byKey(const Key('finance-document-one')), findsNothing);
      await parcel_fixture.choose(tester, 'parcel:two');
      expect(selectedParcel(tester), 'parcel:two');
    },
  );

  testWidgets('initial parcel does not bypass revoked finance access', (
    tester,
  ) async {
    final actor = actors.actor();
    AuthorizationSubject? live;
    final store = _Store();
    await tester.pumpWidget(
      app_fixture.app(
        FinanceDocumentsScreen(
          service: FinanceDocumentService(
            repository: store,
            subject: actor,
            currentSubject: () => live,
          ),
          initialParcelId: 'one',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.reads, 0);
    expect(find.byKey(const Key('finance-parcel-filter')), findsNothing);
    expect(find.byKey(const Key('finance-export-v2')), findsNothing);
  });
}
