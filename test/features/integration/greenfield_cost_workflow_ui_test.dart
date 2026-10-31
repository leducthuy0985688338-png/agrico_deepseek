import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_store.dart';
import 'package:agrico_deepseek/features/integration/domain/production_cost_workflow.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_projection.dart';
import 'package:agrico_deepseek/features/integration/presentation/integration_workspace_screen.dart';

class _ReadStore implements IntegrationStore {
  @override
  Future<IntegrationSnapshot> snapshot(
    String farm,
    String period,
  ) async => IntegrationSnapshot(
    farm: farm,
    period: period,
    sourceCoverageVerified: true,
    tables: {
      for (final name in ProductionCostProjection.requiredTables) name: [],
      'production_source_versions_v2': [
        {
          'farm_id': farm,
          'source_type': 'expenseAllocation',
          'source_id': 'expense',
          'revision': 1,
          'status': 'draft',
          'creator': 'creator',
          'created_at': '2026-10-20T01:00:00Z',
          'payload_digest': 'reviewed-digest',
        },
      ],
      'production_expense_policies_v2': [
        {
          'id': 'expense',
          'farm_id': farm,
          'source_id': 'expense',
          'driver': 'area',
          'money_scale': 2,
          'base_units': 100,
          'currency': 'VND',
          'weights_json':
              '[{"planId":"PLAN-A","units":100,"evidence":"approved area measurement"}]',
        },
      ],
    },
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkflowStore implements ProductionCostWorkflowStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'allocation review is visible and proposal driver has no default',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final subject = AuthorizationSubject(
        userId: 'admin',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      );
      final access = IntegrationService(
        repository: _ReadStore(),
        subject: subject,
        currentSubject: () => subject,
        productionCosts: _WorkflowStore(),
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
          home: IntegrationWorkspaceScreen(service: access),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(
        const ValueKey('production-cost-approval-review'),
      );
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.textContaining('approved area measurement'), findsOneWidget);
      expect(find.textContaining('Số lẻ: 2'), findsOneWidget);
      final propose = find.text('Đề xuất phân bổ');
      await tester.ensureVisible(propose);
      await tester.tap(propose);
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown, findsOneWidget);
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
