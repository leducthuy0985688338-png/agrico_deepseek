import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/finance_filtered_export_test.dart' as documents;
import '../application/finance_parcel_link_test.dart' as actors;
import 'finance_document_details_test.dart' as app_fixture;
import 'finance_document_parcel_filter_test.dart' as parcel_ui;

class _Store implements FinanceDocumentStore {
  final items = [
    documents.document('lak'),
    documents.document('vnd', currency: 'VND'),
    documents.document('receipt', receipt: true),
    documents.document('old', day: 9),
    documents.document('general', parcel: null),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => List.of(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> chooseCurrency(WidgetTester tester, String value) async {
  final selector = find.byKey(const Key('finance-currency-filter'));
  await tester.scrollUntilVisible(
    selector,
    -100,
    scrollable: find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    ),
  );
  final dropdown = tester.widget<DropdownButton<String>>(
    find.descendant(
      of: selector,
      matching: find.byType(DropdownButton<String>),
    ),
  );
  final label =
      (dropdown.items!.singleWhere((item) => item.value == value).child as Text)
          .data!;
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'currency combines with four filters and matches totals and Excel',
    (tester) async {
      final actor = actors.actor();
      final store = _Store();
      final exported = <Excel>[];
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
            pickPeriod: (_, range) async =>
                DateTimeRange(start: date, end: date),
            saveReport: (workbook, name) async {
              exported.add(workbook);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-kind-payment')));
      await tester.tap(find.byKey(const Key('finance-period')));
      await tester.pumpAndSettle();
      await parcel_ui.choose(tester, 'parcel:one');
      await chooseCurrency(tester, 'currency:VND');
      await tester.enterText(find.byKey(const Key('finance-search')), 'ຂໍ້ມູນ');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-document-lak')), findsNothing);
      expect(find.byKey(const Key('finance-document-vnd')), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-filtered-totals')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('finance-filtered-total-VND')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('finance-filtered-total-LAK')), findsNothing);
      await tester.tap(find.byKey(const Key('finance-filtered-totals-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-export-v2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-export-filtered')));
      await tester.pumpAndSettle();
      expect(exported.single['Finance V2'].rows, hasLength(2));
      expect(
        (exported.single['Finance V2'].rows[1][3]!.value as TextCellValue).value
            .toString(),
        'VND',
      );
      await tester
          .widget<RefreshIndicator>(find.byKey(const Key('finance-refresh')))
          .onRefresh();
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('finance-currency-filter'));
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: selector,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .value,
        'currency:VND',
      );
      await tester.tap(find.byKey(const Key('finance-clear-filters')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: selector,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .value,
        'all',
      );
      expect(find.byKey(const Key('finance-clear-filters')), findsNothing);
    },
  );
  testWidgets(
    'currency dropdown respects view revocation and wraps long parcel labels on narrow screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      final initial = actors.actor();
      AuthorizationSubject? live = initial;
      final service = FinanceDocumentService(
        repository: _Store(),
        subject: initial,
        currentSubject: () => live,
      );
      await tester.pumpWidget(
        app_fixture.app(
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
      await chooseCurrency(tester, 'currency:LAK');
      expect(tester.takeException(), isNull);
      live = null;
      await tester.enterText(find.byKey(const Key('finance-search')), 'Mua');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-currency-filter')), findsNothing);
      expect(find.byKey(const Key('finance-document-lak')), findsNothing);
    },
  );
}
