import 'package:agrico_deepseek/features/finance/application/production_cost_report.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AuthorizationSubject actor({
  bool report = true,
  bool expired = false,
  Set<DataScope> scopes = const {DataScope.allFarm},
  String farm = 'farm',
}) => AuthorizationSubject(
  userId: 'user',
  membershipId: 'member',
  farmId: farm,
  permissionCodes: {
    PermissionCodes.financeView,
    if (report) PermissionCodes.reportFinance,
  },
  dataScopes: scopes,
  validUntil: DateTime.now().add(Duration(hours: expired ? -1 : 1)),
);
FinanceDocument document(
  String id,
  int amount, {
  String? parcelId,
  String currency = 'LAK',
  BusinessDocumentKind kind = BusinessDocumentKind.payment,
  String farm = 'farm',
}) => FinanceDocument(
  id: id,
  organizationId: farm,
  code: 'CHI-$id',
  kind: kind,
  occurredAt: DateTime(2026),
  amountMinor: amount,
  currency: currency,
  category: 'Test $id',
  parcelId: parcelId,
);

void main() {
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late ProductionCostSummary service;
  setUp(() {
    store = _Store();
    initial = actor();
    live = initial;
    service = ProductionCostSummary(
      FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => live,
      ),
    );
  });
  test(
    'Excel report has consistent totals, parcel groups and payment details',
    () async {
      store.items = [
        document('one', 1000000, parcelId: 'one'),
        document('two', 2000000),
        document('vnd', 500, parcelId: 'one', currency: 'VND'),
        document('receipt', 9000000, kind: BusinessDocumentKind.receipt),
      ];
      final workbook = await ProductionCostReport(service).workbook();
      final totals = workbook['Totals'].rows;
      expect(totals, hasLength(3));
      expect(totals[1][0]!.value.toString(), 'LAK');
      expect(totals[1][1]!.value.toString(), '3000000');
      expect(totals[2][0]!.value.toString(), 'VND');
      expect(workbook['By Parcel'].rows, hasLength(4));
      expect(workbook['By Parcel'].rows[1][0]!.value.toString(), '');
      expect(workbook['Documents'].rows, hasLength(4));
      expect(
        workbook['Documents'].rows.map((row) => row[0]?.value.toString()),
        isNot(contains('CHI-receipt')),
      );
      expect(workbook.encode(), isNotEmpty);
    },
  );
  test('empty ledger exports valid worksheet headers', () async {
    final workbook = await ProductionCostReport(service).workbook();
    for (final sheet in ['Totals', 'By Parcel', 'Documents']) {
      expect(workbook[sheet].rows, hasLength(1));
    }
  });
  test('revoked report grant prevents file writer from running', () async {
    store.onRead = () {
      live = actor(report: false);
    };
    var saves = 0;
    await expectLater(
      ProductionCostReport(service).exportReport(
        save: (_) async {
          saves++;
        },
      ),
      throwsStateError,
    );
    expect(saves, 0);
  });
  testWidgets('export button saves two reports under distinct filenames', (
    tester,
  ) async {
    store.items = [document('one', 1000000)];
    final names = <String>[];
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
        home: ProductionCostsScreen(
          service: service,
          saveReport: (workbook, name) async {
            names.add(name);
            expect(workbook['Documents'].rows, hasLength(2));
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('costs-export')));
      await tester.pumpAndSettle();
    }
    expect(names, hasLength(2));
    expect(names.toSet(), hasLength(2));
    expect(
      names.every(
        (name) => name.startsWith('BaoCaoChiPhiV2-') && name.endsWith('.xlsx'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'groups payments by parcel and currency while excluding receipts',
    () async {
      store.items = [
        document('a', 1000000, parcelId: 'one'),
        document('b', 2000000, parcelId: 'one'),
        document('c', 400, parcelId: 'one', currency: 'VND'),
        document('d', 500000, parcelId: 'two'),
        document('e', 250000),
        document(
          'receipt',
          99000000,
          parcelId: 'one',
          kind: BusinessDocumentKind.receipt,
        ),
      ];
      final report = await service.load();
      expect(report.groups, hasLength(4));
      expect(
        report.groups
            .singleWhere((g) => g.parcelId == 'one' && g.currency == 'LAK')
            .amountMinor,
        3000000,
      );
      expect(
        report.groups.singleWhere((g) => g.parcelId == null).amountMinor,
        250000,
      );
      expect(report.totals, {'LAK': 3750000, 'VND': 400});
    },
  );
  test(
    'integer precision and unknown historical parcel links are preserved',
    () async {
      store.items = [
        document('a', 9007199254740993, parcelId: 'old'),
        document('b', 7, parcelId: 'old'),
      ];
      final report = await service.load();
      expect(report.groups.single.parcelId, 'old');
      expect(report.groups.single.amountMinor, 9007199254741000);
      expect(report.parcelLabels, isEmpty);
    },
  );
  test('empty or receipts-only ledger returns no expenses', () async {
    expect((await service.load()).groups, isEmpty);
    store.items = [
      document('receipt', 100, kind: BusinessDocumentKind.receipt),
    ];
    expect((await service.load()).groups, isEmpty);
  });
  test(
    'missing report grant, expiration, changed farm and narrow scope deny reads',
    () async {
      for (final subject in <AuthorizationSubject?>[
        null,
        actor(report: false),
        actor(expired: true),
        actor(farm: 'other'),
        actor(scopes: {DataScope.own}),
      ]) {
        live = subject;
        await expectLater(service.load(), throwsStateError);
      }
      expect(store.reads, 0);
    },
  );
  test('report revoked during a read does not return totals', () async {
    store.onRead = () {
      live = actor(report: false);
    };
    await expectLater(service.load(), throwsStateError);
  });
  test('foreign documents are rejected by the finance boundary', () async {
    store.items = [document('foreign', 100, farm: 'other')];
    await expectLater(service.load(), throwsStateError);
  });
  testWidgets('screen groups general payments and exposes source documents', (
    tester,
  ) async {
    store.items = [document('one', 1000000)];
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
        home: ProductionCostsScreen(service: service),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Tổng chi: 1.000.000 LAK'), findsOneWidget);
    final group = find.byKey(const Key('costs-group-general-LAK'));
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(find.text('CHI-one · Test one'), findsOneWidget);
    store.items = [];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Chưa có chứng từ Chi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [];
  int reads = 0;
  void Function()? onRead;
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    onRead?.call();
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
