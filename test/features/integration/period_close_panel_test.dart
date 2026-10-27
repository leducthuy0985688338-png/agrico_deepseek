import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
import 'package:agrico_deepseek/features/integration/application/period_close_service.dart';
import 'package:agrico_deepseek/features/integration/domain/period_close.dart';
import 'package:agrico_deepseek/features/integration/presentation/period_close_panel.dart';
import 'integration_workspace_screen_test.dart' show MemoryIntegration;

class MemoryClosing implements PeriodCloseStore {
  bool locked = false;
  int writes = 0;
  List<String> issues = [];
  @override
  Future<PeriodReview> review(String farm, String period) async => PeriodReview(
    period: period,
    revision: writes,
    closed: locked,
    token: 'token',
    issues: issues,
    history: [],
  );
  @override
  Future<void> close(
    String farm,
    String period,
    String token,
    int revision,
    String reason,
    String actor,
    void Function() authorize,
  ) async {
    authorize();
    locked = true;
    writes++;
  }

  @override
  Future<void> reopen(
    String farm,
    String period,
    int revision,
    String reason,
    String actor,
    void Function() authorize,
  ) async {
    authorize();
    locked = false;
    writes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(
    WidgetTester tester,
    MemoryClosing repository, {
    bool approving = true,
  }) async {
    final user = AuthorizationSubject(
      userId: 'a',
      membershipId: 'm',
      farmId: 'f',
      permissionCodes: {
        ...IntegrationService.readPermissions,
        if (approving) PermissionCodes.financeApprove,
        if (approving) PermissionCodes.auditReview,
        if (approving) PermissionCodes.financeCorrect,
      },
      dataScopes: {DataScope.allFarm},
    );
    final access = IntegrationService(
      repository: MemoryIntegration(),
      subject: user,
      currentSubject: () => user,
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
        home: Scaffold(
          body: SingleChildScrollView(
            child: PeriodClosePanel(
              service: PeriodCloseService(
                repository: repository,
                access: access,
              ),
              period: '2026-09',
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'closing requires a reason and an explicit confirmation; reopening preserves the workflow',
    (tester) async {
      final repo = MemoryClosing();
      await open(tester, repo);
      await tester.tap(find.text('Khóa kỳ'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do'), findsOneWidget);
      expect(repo.writes, 0);
      await tester.enterText(find.byType(TextFormField), 'Chốt tháng');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(find.text('Mở lại kỳ'), findsOneWidget);
      await tester.tap(find.text('Mở lại kỳ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Sửa nguồn có lý do');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(repo.writes, 2);
      expect(repo.locked, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unresolved reconciliation disables closing and read-only access hides write actions',
    (tester) async {
      final repo = MemoryClosing()..issues = ['unlinkedSalary:1'];
      await open(tester, repo);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Khóa kỳ'),
      );
      expect(button.onPressed, isNull);
      expect(repo.writes, 0);
      await open(tester, repo, approving: false);
      expect(find.text('Khóa kỳ'), findsNothing);
      expect(find.text('Mở lại kỳ'), findsNothing);
    },
  );
  testWidgets('canceling closing does not write a period event', (
    tester,
  ) async {
    final repo = MemoryClosing();
    await open(tester, repo);
    await tester.tap(find.text('Khóa kỳ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    expect(repo.locked, isFalse);
  });
  test('closed-period failures have an actionable localized message', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = AppLocalizations(locale);
      expect(
        l.failure(StateError('ACCOUNTING_PERIOD_CLOSED'), 'finance.saveFailed'),
        l.text('period.closedError'),
      );
      expect(
        l.failure(StateError('Other'), 'finance.saveFailed'),
        l.text('finance.saveFailed'),
      );
    }
  });
}
