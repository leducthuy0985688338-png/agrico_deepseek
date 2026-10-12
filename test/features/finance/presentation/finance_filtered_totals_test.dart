import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_filter.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/finance_v2_report.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finance_document_details_test.dart' as fixture;
import 'finance_document_parcel_filter_test.dart' as parcel_ui;

AuthorizationSubject actor() => AuthorizationSubject(
  userId: 'user',
  membershipId: 'member',
  farmId: 'farm',
  permissionCodes: {PermissionCodes.financeView},
  dataScopes: const {DataScope.allFarm},
  validUntil: DateTime.now().add(const Duration(hours: 1)),
);
FinanceDocument document(
  String id, {
  String currency = 'LAK',
  bool receipt = false,
  int day = 12,
  String? parcel = 'one',
  int amount = 1000000,
}) => FinanceDocument(
  id: id,
  organizationId: 'farm',
  code: id,
  kind: receipt ? BusinessDocumentKind.receipt : BusinessDocumentKind.payment,
  occurredAt: DateTime(2026, 10, day),
  amountMinor: amount,
  currency: currency,
  category: 'pick',
  description: 'ຂໍ້ມູນ',
  parcelId: parcel,
);

class _Store implements FinanceDocumentStore {
  void Function()? onRead;
  List<FinanceDocument> items = [
    document('one'),
    document('vnd', currency: 'VND'),
    document('receipt', receipt: true),
    document('old', day: 9),
    document('general', parcel: null),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    onRead?.call();
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final button = find.byKey(const Key('finance-filtered-totals'));
  final dialog = find.byKey(const Key('finance-filtered-totals-dialog'));
  final close = find.byKey(const Key('finance-filtered-totals-close'));
  testWidgets(
    'view-only filtered totals match Excel per currency with all four filters',
    (tester) async {
      final initial = actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => initial,
      );
      final from = DateTime(2026, 10, 12);
      await tester.pumpWidget(
        fixture.app(
          FinanceDocumentsScreen(
            service: service,
            pickPeriod: (_, range) async =>
                DateTimeRange(start: from, end: from),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-kind-payment')));
      await tester.tap(find.byKey(const Key('finance-period')));
      await tester.pumpAndSettle();
      await parcel_ui.choose(tester, 'parcel:one');
      await tester.enterText(find.byKey(const Key('finance-search')), 'ຂໍ້ມູນ');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('Số chứng từ: 2')),
        findsOneWidget,
      );
      final workbook = await FinanceV2Report(store).workbook(
        'farm',
        filter: FinanceDocumentFilter(
          query: 'ຂໍ້ມູນ',
          kind: BusinessDocumentKind.payment,
          from: from,
          to: from,
          parcel: 'parcel:one',
        ),
      );
      for (final row in workbook['Totals V2'].rows.skip(1)) {
        final currency = (row[0]!.value as TextCellValue).value.toString();
        final card = find.byKey(Key('finance-filtered-total-$currency'));
        expect(
          find.descendant(of: card, matching: find.text('Thu: 0')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Chi: 1.000.000')),
          findsOneWidget,
        );
        expect((row[3]!.value as IntCellValue).value, -1000000);
        expect(
          find.descendant(
            of: card,
            matching: find.text('Chênh lệch thu chi: -1.000.000'),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('finance-search')))
            .controller!
            .text,
        'ຂໍ້ມູນ',
      );
      expect(find.byKey(const Key('finance-export-v2')), findsNothing);
    },
  );
  testWidgets(
    'totals read fresh persisted values and empty results show zero count',
    (tester) async {
      final initial = actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => initial,
      );
      await tester.pumpWidget(
        fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      store.items = [document('new', amount: 2000000)];
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('Chi: 2.000.000')),
        findsOneWidget,
      );
      await tester.tap(close);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('finance-search')),
        'missing',
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('Số chứng từ: 0')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('finance-filtered-total-LAK')), findsNothing);
    },
  );
  testWidgets('revocation during totals read does not open dialog', (
    tester,
  ) async {
    final initial = actor();
    AuthorizationSubject? live = initial;
    final store = _Store();
    final service = FinanceDocumentService(
      repository: store,
      subject: initial,
      currentSubject: () => live,
    );
    await tester.pumpWidget(
      fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    store.onRead = () => live = null;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });
  testWidgets('totals scroll and close on narrow screen with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initial = actor();
    final store = _Store()
      ..items = [for (var i = 0; i < 8; i++) document('d$i', currency: 'X$i')];
    final service = FinanceDocumentService(
      repository: store,
      subject: initial,
      currentSubject: () => initial,
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
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('X7'),
      100,
      scrollable: find.descendant(
        of: dialog,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('X7'), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
