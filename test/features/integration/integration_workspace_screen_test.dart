import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/theme/app_theme.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_store.dart';
import 'package:agrico_deepseek/features/integration/presentation/integration_workspace_screen.dart';

class MemoryIntegration implements IntegrationStore {
  int reads = 0, links = 0;
  String? adopted;
  @override
  Future<IntegrationSnapshot> snapshot(String farm, String period) async {
    reads++;
    return IntegrationSnapshot(
      farm: farm,
      period: period,
      tables: {
        'personnel_payments_v1': [
          {
            'id': 'old',
            'amount': '1',
            'currency': 'VND',
            'business_day': '2026-10-25',
          },
        ],
        'finance_documents_v2': [
          {
            'id': 'cash',
            'organization_id': farm,
            'code': 'CHI-202610-001',
            'kind': 'CHI',
            'occurred_at': '2026-10-25T00:00:00.000',
            'amount_minor': 1,
            'currency': 'VND',
            'category': 'Payroll',
          },
        ],
      },
    );
  }

  @override
  Future<void> linkSalary(
    String farm,
    String id,
    String actorId, {
    String? existingFinanceId,
  }) async {
    links++;
    adopted = existingFinanceId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(
    WidgetTester tester,
    MemoryIntegration repository, {
    bool full = true,
    bool export = false,
  }) async {
    final user = AuthorizationSubject(
      userId: 'a',
      membershipId: 'm',
      farmId: 'f',
      permissionCodes: full
          ? {
              ...IntegrationService.readPermissions,
              PermissionCodes.payrollApprove,
              PermissionCodes.cashRecord,
              if (export) PermissionCodes.dataExport,
            }
          : const {PermissionCodes.financeView},
      dataScopes: const {DataScope.allFarm},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: IntegrationWorkspaceScreen(
          service: IntegrationService(
            repository: repository,
            subject: user,
            currentSubject: () => user,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('report screen respects sensitive access and export permission', (
    tester,
  ) async {
    final repo = MemoryIntegration();
    await open(tester, repo, full: false);
    expect(repo.reads, 0);
    expect(find.text('Không có quyền xem'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, repo);
    expect(repo.reads, 1);
    expect(find.text('Xuất Excel đủ 20 trang'), findsNothing);
    expect(find.text('Kiểm tra đối soát'), findsOneWidget);
  });
  testWidgets(
    'historical cash adoption is selected by readable code and requires confirmation',
    (tester) async {
      final repo = MemoryIntegration();
      await open(tester, repo);
      await tester.tap(find.text('Lương / sổ tiền'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nối sổ tiền'));
      await tester.pumpAndSettle();
      expect(repo.links, 0);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(repo.links, 0);
      await tester.tap(find.text('Nối sổ tiền'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CHI-202610-001 · 1 VND').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.links, 1);
      expect(repo.adopted, 'cash');
    },
  );
}
