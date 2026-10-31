import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/approval/approval_administration.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/integration/presentation/approval_policy_panel.dart';
import 'package:agrico_deepseek/app_v2/v2_settings_screen.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_store.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_snapshot.dart';
import 'package:agrico_deepseek/features/integration/application/integration_service.dart';
import 'package:agrico_deepseek/features/integration/presentation/integration_workspace_screen.dart';

class _NoBusinessReads implements IntegrationStore {
  int reads = 0;
  @override
  Future<IntegrationSnapshot> snapshot(String farm, String period) async {
    reads++;
    throw StateError('Policy-only authority must not read business snapshots.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Business operation forbidden.');
}

class _Store implements ApprovalAdministration {
  int reads = 0;
  int activations = 0;
  String? activationReason;
  List<Map<String, Object?>> rows = [];
  @override
  Future<void> publishDraft(
    ApprovalKind kind,
    String currency,
    int version,
  ) async => throw StateError('Not used');
  @override
  Future<List<Map<String, Object?>>> list() async {
    reads++;
    return rows;
  }

  @override
  Future<void> propose(DocumentApprovalPolicy policy, String reason) async =>
      throw StateError('Not used');
  @override
  Future<void> activate(
    ApprovalKind kind,
    String currency,
    int version,
    int expectedActive,
    String reason,
  ) async {
    activations++;
    activationReason = reason;
  }

  @override
  Future<List<Map<String, Object?>>> policyHistory() async => [];
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Store store,
    String language,
    Set<String> permissions,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('vi'), Locale('en'), Locale('lo')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ListView(
            children: [
              ApprovalPolicyPanel(
                store: store,
                can: permissions.contains,
                farm: 'farm',
                actor: 'manager',
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'ordinary technical admin has no policy controls or implicit reads',
    (tester) async {
      final store = _Store();
      await show(tester, store, 'en', {});
      expect(find.byType(ExpansionTile), findsNothing);
      expect(store.reads, 0);
    },
  );
  for (final language in ['vi', 'en', 'lo']) {
    testWidgets(
      'policy panel translates $language and requires explicit draft action',
      (tester) async {
        final store = _Store();
        await show(tester, store, language, {
          ApprovalRules.policyManage,
          ApprovalRules.limitManage,
        });
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        expect(store.reads, 0);
        final draft = switch (language) {
          'vi' => 'Đề xuất draft',
          'lo' => 'ສະເໜີຮ່າງ',
          _ => 'Propose draft',
        };
        await tester.tap(find.text(draft));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('approval-kind')), findsOneWidget);
        expect(find.byKey(const ValueKey('approval-currency')), findsOneWidget);
        final fields = tester
            .widgetList<TextField>(find.byType(TextField))
            .toList();
        expect(fields, hasLength(3));
        expect(fields.every((f) => f.controller!.text.isEmpty), isTrue);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(store.reads, 0);
      },
    );
  }
  testWidgets(
    'independent activator can inspect policies without management privileges',
    (tester) async {
      final store = _Store();
      await show(tester, store, 'en', {ApprovalRules.policyActivate});
      expect(find.byType(ExpansionTile), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Propose draft'), findsNothing);
      await tester.tap(find.text('Load policies'));
      await tester.pumpAndSettle();
      expect(store.reads, 1);
    },
  );
  testWidgets(
    'cancelling a populated policy draft keeps controllers alive through route dismissal',
    (tester) async {
      await show(tester, _Store(), 'en', {
        ApprovalRules.policyManage,
        ApprovalRules.limitManage,
      });
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propose draft'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Synthetic cancellation reason',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'activation-only reviewer confirms a draft without authoring or disposed controllers',
    (tester) async {
      final store = _Store()
        ..rows = [
          {
            'kind': 'materialIssue',
            'currency': 'VND',
            'version': 1,
            'state': 'draft',
            'changed_by': 'separate-policy-author',
            'changed_at': '2026-10-31T00:00:00Z',
            'payload': '{}',
          },
        ];
      await show(tester, store, 'en', {ApprovalRules.policyActivate});
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load policies'));
      await tester.pumpAndSettle();
      expect(find.text('Propose draft'), findsNothing);
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Independent synthetic activation reason',
      );
      await tester.tap(find.text('Request activation'));
      await tester.pumpAndSettle();
      expect(store.activations, 1);
      expect(store.activationReason, 'Independent synthetic activation reason');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'policy-only activator enters existing integration workspace without financial read rights',
    (tester) async {
      final policies = _Store(), business = _NoBusinessReads();
      const subject = AuthorizationSubject(
        userId: 'activator',
        membershipId: 'activator',
        farmId: 'farm',
        permissionCodes: {ApprovalRules.policyActivate},
        dataScopes: {DataScope.allFarm},
      );
      final access = IntegrationService(
        repository: business,
        subject: subject,
        currentSubject: () => subject,
        approvalPolicies: policies,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          home: IntegrationWorkspaceScreen(service: access),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ApprovalPolicyPanel), findsOneWidget);
      expect(business.reads, 0);
      expect(find.text('Payroll / cash'), findsNothing);
    },
  );

  testWidgets(
    'settings entry reaches existing policy workspace without reading payroll or cash',
    (tester) async {
      final business = _NoBusinessReads(), policies = _Store();
      const subject = AuthorizationSubject(
        userId: 'activator',
        membershipId: 'activator',
        farmId: 'farm',
        permissionCodes: {ApprovalRules.policyActivate},
        dataScopes: {DataScope.allFarm},
      );
      final service = IntegrationService(
        repository: business,
        subject: subject,
        currentSubject: () => subject,
        approvalPolicies: policies,
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          home: V2SettingsScreen(
            onOpenApprovalPolicies: service.canAdministerApproval
                ? () => navigator.currentState!.push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          IntegrationWorkspaceScreen(service: service),
                    ),
                  )
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('company-approval-policy-open')));
      await tester.pumpAndSettle();
      expect(find.byType(ApprovalPolicyPanel), findsOneWidget);
      expect(business.reads, 0);
      expect(find.text('Payroll / cash'), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load policies'));
      await tester.pumpAndSettle();
      expect(policies.reads, 1);
      expect(business.reads, 0);
    },
  );
}
