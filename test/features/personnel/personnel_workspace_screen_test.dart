import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/personnel/application/personnel_service.dart';
import 'package:agrico_deepseek/features/personnel/presentation/personnel_workspace_screen.dart';

class MemoryPersonnel
    implements PersonnelRepository, ProductionLaborCostRepository {
  int rateReads = 0;
  final savedRates = <PayRate>[];
  final drafts = <LaborEntryDraft>[];
  @override
  Future<List<EmployeeCard>> employees(
    String farmId, {
    required bool sensitive,
  }) async => const [
    EmployeeCard(
      workerId: 'w',
      code: 'CN-000001',
      name: 'Worker',
      active: true,
    ),
  ];
  @override
  Future<List<PayRate>> rates(String farmId) async {
    rateReads++;
    return savedRates;
  }

  @override
  Future<void> createRate(PayRate r, String actorId) async {
    r.validate();
    savedRates.add(r);
  }

  @override
  Future<void> createEntry(LaborEntryDraft d, String actorId) async {
    d.validate();
    drafts.add(d);
  }

  @override
  Future<List<LaborEntryRecord>> entries(
    String farmId, {
    required bool money,
  }) async => [];
  @override
  Future<List<PayrollRecordV2>> payrolls(String farmId) async => [];
  @override
  Future<List<SalaryPayment>> payments(String farmId) async => [];
  @override
  Future<List<ProductionLaborCost>> productionLaborCosts(String farmId) async =>
      [];
  @override
  Future<List<PersonnelPlanChoice>> planChoices(String farmId) async => [];
  @override
  Future<List<PersonnelTaskChoice>> taskChoices(String farmId) async => [];
  @override
  Future<void> saveProfile(EmployeeProfile p, String actorId) async =>
      throw UnimplementedError();
  @override
  Future<void> approveEntry(
    String farmId,
    String id,
    int revision,
    String actorId,
  ) async => throw UnimplementedError();
  @override
  Future<void> voidEntry(
    String farmId,
    String id,
    int revision,
    String reason,
    String actorId,
  ) async => throw UnimplementedError();
  @override
  Future<void> createPayroll(PayrollDraft d, String actorId) async =>
      throw UnimplementedError();
  @override
  Future<void> approvePayroll(String farmId, String id, String actorId) async =>
      throw UnimplementedError();
  @override
  Future<void> cancelPayroll(
    String farmId,
    String id,
    String reason,
    String actorId,
  ) async => throw UnimplementedError();
  @override
  Future<void> recordPayment(
    String farmId,
    String id,
    String payrollId,
    String amount,
    String currency,
    String day,
    String note,
    String actorId,
  ) async => throw UnimplementedError();
}

void main() {
  final admin = AuthorizationSubject(
    userId: 'a',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: PermissionCodes.values,
    dataScopes: const {DataScope.allFarm},
  );
  const clerk = AuthorizationSubject(
    userId: 'c',
    membershipId: 'm',
    farmId: 'f',
    permissionCodes: {
      PermissionCodes.employeeView,
      PermissionCodes.attendanceRecord,
    },
    dataScopes: {DataScope.allFarm},
  );
  Future<void> open(
    WidgetTester tester,
    MemoryPersonnel repo,
    AuthorizationSubject subject,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
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
          service: PersonnelService(repo, currentSubject: () => subject),
          subject: subject,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String key, String text) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'attendance clerk never fetches salary configuration or sees payroll tabs',
    (tester) async {
      final repo = MemoryPersonnel();
      await open(tester, repo, clerk);
      expect(repo.rateReads, 0);
      expect(find.text('Mức lương'), findsNothing);
      expect(find.text('Bảng lương'), findsNothing);
      expect(find.byKey(const Key('hr-export')), findsNothing);
    },
  );
  testWidgets(
    'rate creation requires explicit currency rounding and precision',
    (tester) async {
      final repo = MemoryPersonnel();
      await open(tester, repo, admin);
      await tester.tap(find.text('Mức lương'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hr-add-rate')));
      await tester.pumpAndSettle();
      await select(tester, 'hr-field-worker-w', 'CN-000001 · Worker');
      await select(
        tester,
        'hr-field-basis-hourly:daily:piece',
        'Theo công chuẩn',
      );
      await tester.enterText(find.byKey(const Key('hr-field-rate')), '80000');
      await tester.tap(find.byKey(const Key('hr-form-save')));
      await tester.pumpAndSettle();
      expect(repo.savedRates, isEmpty);
      expect(find.byKey(const Key('hr-save-error')), findsOneWidget);
      await select(tester, 'hr-field-currency-VND:LAK', 'VND');
      await select(
        tester,
        'hr-field-round-halfUp:down',
        'Gần nhất; đúng nửa làm tròn lên',
      );
      await select(tester, 'hr-field-scale-0:1:2:3:4:5:6', '0');
      await tester.tap(find.byKey(const Key('hr-form-save')));
      await tester.pumpAndSettle();
      expect(repo.savedRates.single.rate, '80000');
      expect(repo.savedRates.single.standardMinutes, 480);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clerk records a draft with eight hours and no invented wage rate',
    (tester) async {
      final repo = MemoryPersonnel();
      await open(tester, repo, clerk);
      await tester.tap(find.text('Chấm công'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hr-add-entry')));
      await tester.pumpAndSettle();
      await select(tester, 'hr-field-worker-w', 'CN-000001 · Worker');
      await tester.tap(find.byKey(const Key('hr-form-save')));
      await tester.pumpAndSettle();
      expect(repo.drafts.single.regularMinutes, 480);
      expect(repo.drafts.single.overtimeMinutes, 0);
      expect(repo.rateReads, 0);
    },
  );
}
