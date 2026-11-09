import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_service.dart';
import 'package:agrico_deepseek/features/personnel/presentation/personnel_workspace_screen.dart';
import 'personnel_workspace_screen_test.dart' show MemoryPersonnel;

class AdjustmentMemory extends MemoryPersonnel
    implements PayrollAdjustmentRepository {
  final created = <PayrollAdjustmentDraft>[];
  final approved = <String>[];
  final recordedRefunds = <Map<String, String?>>[];
  @override
  Future<List<PayrollRecordV2>> payrolls(String farm) async => [
    PayrollRecordV2(
      id: 'salary',
      workerId: 'w',
      workerName: 'Worker',
      period: LaborMoney.day(DateTime.now()).substring(0, 7),
      currency: 'VND',
      status: 'approved',
      regular: '100',
      overtime: '0',
      piece: '0',
      allowance: '0',
      bonus: '0',
      advance: '0',
      deduction: '0',
      net: '100',
      paid:
          recordedRefunds.isEmpty || recordedRefunds.last['reversesId'] != null
          ? '100'
          : '80',
      note: 'Original approved source',
      code: 'LUONG-TEST-001',
      adjustmentTotal: approved.isEmpty ? '-20' : '-10',
      adjustmentRevision: approved.isEmpty ? 1 : 2,
    ),
  ];
  @override
  Future<List<PersonnelPlanChoice>> payrollAdjustmentPlans(
    String farm,
    String payroll,
  ) async => [];
  @override
  Future<void> createPayrollAdjustment(
    PayrollAdjustmentDraft draft,
    String actor,
  ) async {
    draft.validate();
    created.add(draft);
  }

  @override
  Future<void> approvePayrollAdjustment(
    String farm,
    String id,
    String actor,
  ) async {
    approved.add(id);
  }

  @override
  Future<void> cancelPayrollAdjustment(
    String farm,
    String id,
    String actor,
  ) async {}
  @override
  Future<List<PayrollAdjustmentRecord>> payrollAdjustments(String farm) async =>
      [
        for (final d in created)
          PayrollAdjustmentRecord(
            draft: d,
            code: 'DCL-TEST-001',
            status: approved.contains(d.id) ? 'approved' : 'draft',
            creator: 'creator',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            beforeNet: '80',
            approver: approved.contains(d.id) ? 'approver' : null,
          ),
      ];
  @override
  Future<List<PayrollRefund>> payrollRefunds(String farm) async => [
    for (final r in recordedRefunds)
      PayrollRefund(
        id: r['id']!,
        payrollId: 'salary',
        amount: r['amount']!,
        currency: 'VND',
        day: r['day']!,
        reason: r['reason']!,
        actor: 'admin',
        financeId: 'cash-${r['id']}',
        reversesId: r['reversesId'],
      ),
  ];
  @override
  Future<void> refundPayroll(
    String farm,
    String id,
    String payroll,
    String amount,
    String currency,
    String day,
    String reason,
    String actor, {
    String? reversesId,
  }) async {
    recordedRefunds.add({
      'id': id,
      'amount': amount,
      'day': day,
      'reason': reason,
      'reversesId': reversesId,
    });
  }

  @override
  Future<List<ProductionLaborCost>> payrollAdjustmentCosts(String farm) async =>
      [];
}

void main() {
  final admin = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  Future<void> open(
    WidgetTester tester,
    AdjustmentMemory repo, {
    AuthorizationSubject? subject,
  }) async {
    final user = subject ?? admin;
    await tester.binding.setSurfaceSize(const Size(1100, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
        home: PersonnelWorkspaceScreen(
          service: PersonnelService(repo, currentSubject: () => user),
          subject: user,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bảng lương'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'proposal retains the approved source and approval shows the corrected amount before confirmation',
    (tester) async {
      final repo = AdjustmentMemory();
      await open(tester, repo);
      await tap(tester, find.byKey(const Key('hr-adjustment-create-salary')));
      await tester.enterText(find.byKey(const Key('hr-field-delta')), '10');
      await tester.enterText(
        find.byKey(const Key('hr-field-reason')),
        'Approved correction reason',
      );
      await tap(tester, find.byKey(const Key('hr-form-save')));
      expect(repo.created.single.delta, '10');
      expect(repo.created.single.expectedRevision, 1);
      expect(repo.created.single.payrollId, 'salary');
      expect(repo.approved, isEmpty);
      await tap(
        tester,
        find.byKey(Key('hr-adjustment-approve-${repo.created.single.id}')),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Lương sau điều chỉnh: 90'), findsOneWidget);
      expect(repo.approved, isEmpty);
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      expect(repo.approved, [repo.created.single.id]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'employee receivable offers a partial refund form and an append-only reversal action',
    (tester) async {
      final repo = AdjustmentMemory();
      await open(tester, repo);
      await tap(tester, find.byKey(const Key('hr-payroll-refund-salary')));
      await tester.enterText(
        find.byKey(const Key('hr-field-reason')),
        'Employee returned cash',
      );
      await tap(tester, find.byKey(const Key('hr-form-save')));
      expect(repo.recordedRefunds.single['amount'], '20');
      expect(repo.recordedRefunds.single['reversesId'], isNull);
      final original = repo.recordedRefunds.single['id'];
      await tap(tester, find.text('Đảo thu hoàn').last);
      await tester.enterText(
        find.byKey(const Key('hr-field-reason')),
        'Original refund entry was mistaken',
      );
      await tap(tester, find.byKey(const Key('hr-form-save')));
      expect(repo.recordedRefunds.last['reversesId'], original);
      expect(repo.recordedRefunds.last['amount'], '20');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'payroll read permission does not expose correction approval or refund actions',
    (tester) async {
      final repo = AdjustmentMemory();
      const reader = AuthorizationSubject(
        userId: 'reader',
        membershipId: 'm',
        farmId: 'f',
        permissionCodes: {
          PermissionCodes.employeeView,
          PermissionCodes.payrollView,
        },
        dataScopes: {DataScope.allFarm},
      );
      await open(tester, repo, subject: reader);
      expect(
        find.byKey(const Key('hr-adjustment-create-salary')),
        findsNothing,
      );
      expect(find.byKey(const Key('hr-payroll-refund-salary')), findsNothing);
      expect(repo.created, isEmpty);
      expect(repo.recordedRefunds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
