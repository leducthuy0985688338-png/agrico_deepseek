import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AuthorizationSubject actor({bool view = true}) => AuthorizationSubject(
  userId: 'user',
  membershipId: 'member',
  farmId: 'farm',
  permissionCodes: {
    if (view) PermissionCodes.financeView,
    if (view) PermissionCodes.cashView,
  },
  dataScopes: const {DataScope.allFarm},
  validUntil: DateTime.now().add(const Duration(hours: 1)),
);
FinanceDocument document({
  String farm = 'farm',
  int amount = 1000000,
  String? notes,
  BusinessDocumentKind kind = BusinessDocumentKind.payment,
}) => FinanceDocument(
  id: 'one',
  organizationId: farm,
  code: 'CHI-202610-001',
  kind: kind,
  occurredAt: DateTime(2026, 10, 12),
  amountMinor: amount,
  currency: 'LAK',
  category: 'Nội dung dài để kiểm tra hiển thị trên điện thoại nhỏ',
  description: notes,
);
Widget app(Widget home) => MaterialApp(
  locale: const Locale('vi'),
  supportedLocales: const [Locale('vi')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late FinanceDocumentService service;
  setUp(() {
    store = _Store()..items = [document()];
    initial = actor();
    live = initial;
    service = FinanceDocumentService(
      repository: store,
      subject: initial,
      currentSubject: () => live,
    );
  });
  test(
    'details read the persisted document and preserve optional values',
    () async {
      final (saved, label) = await service.details('one');
      expect(saved.amountMinor, 1000000);
      expect(saved.parcelId, isNull);
      expect(label, isNull);
      store.items = [document(amount: 2000000, notes: 'ຂໍ້ມູນ')];
      expect((await service.details('one')).$1.description, 'ຂໍ້ມູນ');
    },
  );
  test('unknown and foreign documents cannot be opened', () async {
    await expectLater(service.details('missing'), throwsStateError);
    await expectLater(service.details(''), throwsFormatException);
    store.items = [document(farm: 'other')];
    await expectLater(service.details('one'), throwsStateError);
  });
  test(
    'revoked permission during a detail read prevents data return',
    () async {
      store.onRead = () {
        live = actor(view: false);
      };
      await expectLater(service.details('one'), throwsStateError);
    },
  );
  testWidgets(
    'view-only details show fresh values and scroll on a small screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(FinanceDocumentsScreen(service: service)));
      await tester.pump();
      await tester.pumpAndSettle();
      store.items = [
        document(amount: 2000000, notes: List.filled(40, 'ຂໍ້ມູນ ').join()),
      ];
      await tester.scrollUntilVisible(
        find.byKey(const Key('finance-document-one')),
        100,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-document-one')));
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết chứng từ'), findsOneWidget);
      final values = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((value) => value.data)
          .toList();
      expect(values, contains('Số tiền: 2.000.000 LAK'));
      expect(values, contains('Loại chứng từ: Chi'));
      expect(values, contains('Ngày chứng từ: 2026-10-12'));
      expect(values, contains('Lô đất: Chứng từ chung (không gắn lô đất)'));
      expect(find.byKey(const Key('finance-save')), findsNothing);
      await tester.tap(find.byKey(const Key('finance-details-close')));
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết chứng từ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('revocation after list load does not open a details dialog', (
    tester,
  ) async {
    await tester.pumpWidget(app(FinanceDocumentsScreen(service: service)));
    await tester.pump();
    await tester.pumpAndSettle();
    live = actor(view: false);
    await tester.tap(find.byKey(const Key('finance-document-one')));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết chứng từ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [];
  void Function()? onRead;
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
