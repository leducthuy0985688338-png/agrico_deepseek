import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/trade/application/trade_service.dart';
import 'package:agrico_deepseek/features/trade/presentation/trade_workspace_screen.dart';

class MemoryTrade implements TradeRepository {
  final drafts = <TradeDraft>[];
  int cashReads = 0;
  @override
  Future<List<TradeRecord>> documents(String farm) async => [
    for (final d in drafts)
      TradeRecord(d, 'CP-202610-001', 'draft', 0, const {}, '0'),
  ];
  @override
  Future<List<FinishedLot>> lots(String farm) async => [];
  @override
  Future<List<TradePayment>> payments(String farm) async => [];
  @override
  Future<List<Map<String, Object?>>> cashBook(String farm) async {
    cashReads++;
    return [];
  }

  @override
  Future<List<Map<String, Object?>>> choices(String farm, String kind) async =>
      [
        {'id': kind, 'code': kind, 'name': 'Choice $kind'},
      ];
  @override
  Future<void> create(String farm, TradeDraft d, String actor) async {
    d.validate();
    drafts.add(d);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(
    WidgetTester tester,
    MemoryTrade repo,
    Set<String> permissions,
  ) async {
    final user = AuthorizationSubject(
      userId: 'a',
      membershipId: 'a',
      farmId: 'f',
      permissionCodes: permissions,
      dataScopes: const {DataScope.allFarm},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: TradeWorkspaceScreen(
          service: TradeService(
            repo,
            subject: user,
            currentSubject: () => user,
          ),
          openCatalog: () {},
          openCash: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(Key('trade-$key'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(text.trim()).last);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(Key('trade-$key'));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  testWidgets('reader cannot create or fetch restricted cash book', (
    tester,
  ) async {
    final repo = MemoryTrade();
    await open(tester, repo, {PermissionCodes.financeView});
    expect(find.text('Thêm'), findsNothing);
    expect(find.text('Xuất Excel'), findsNothing);
    expect(repo.cashReads, 0);
    expect(find.byIcon(Icons.account_balance_wallet), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('harvest requires explicit currency and rounding before saving', (
    tester,
  ) async {
    final repo = MemoryTrade();
    await open(tester, repo, PermissionCodes.values.toSet());
    await tester.tap(find.text('Thêm').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu nháp'));
    await tester.pumpAndSettle();
    expect(repo.drafts, isEmpty);
    expect(find.text('Nhập hoặc chọn rõ giá trị'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'expense save reload remains synchronous and preserves chosen treatment',
    (tester) async {
      final repo = MemoryTrade();
      await open(tester, repo, PermissionCodes.values.toSet());
      await tester.tap(find.text('Khoản phải trả khác'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm').first);
      await tester.pumpAndSettle();
      await choose(tester, 'currency', 'VND');
      await choose(tester, 'party', 'supplier · Choice supplier ');
      await choose(tester, 'rounding', 'Gần nhất, nửa lên');
      await choose(tester, 'treatment', 'Chi phí kỳ, chưa nằm trong giá thành');
      await enter(tester, 'note', 'Transport');
      await enter(tester, 'price1', '12');
      await enter(tester, 'reference', 'CP001');
      await tester.tap(find.text('Lưu nháp'));
      await tester.pumpAndSettle();
      expect(repo.drafts.single.expenseTreatment, 'periodExpense');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
