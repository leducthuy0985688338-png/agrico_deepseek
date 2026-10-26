import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/machines/application/machine_service.dart';
import 'package:agrico_deepseek/features/machines/presentation/machine_workspace_screen.dart';

class MemoryMachines implements MachineRepository {
  int rateReads = 0, expenseReads = 0, profileSaves = 0;
  @override
  Future<List<MachineCard>> machines(String farm) async => const [
    MachineCard('m', 'MM-000001', 'Tractor', true, {'meterUnit': 'hour'}, 0),
  ];
  @override
  Future<List<MachineRate>> rates(String farm) async {
    rateReads++;
    return [];
  }

  @override
  Future<List<MachineRecord<MachineRun>>> runs(
    String farm, {
    bool money = true,
  }) async => [];
  @override
  Future<List<MachineRecord<MachineExpense>>> expenses(String farm) async {
    expenseReads++;
    return [];
  }

  @override
  Future<List<Map<String, Object?>>> plans(String farm) async => [];
  @override
  Future<List<Map<String, Object?>>> workers(String farm) async => [];
  @override
  Future<List<ProductionMachineCost>> productionMachineCosts(
    String farm,
  ) async => [];
  @override
  Future<void> profile(
    String farm,
    String machine,
    int revision,
    Map<String, String> values,
    String actor,
  ) async {
    profileSaves++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(
    WidgetTester tester,
    MemoryMachines repo,
    Set<String> permissions,
  ) async {
    final subject = AuthorizationSubject(
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
        home: MachineWorkspaceScreen(
          service: MachineService(repo, currentSubject: () => subject),
          subject: subject,
          openCatalog: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('operator cannot fetch financial rate or expense tabs', (
    tester,
  ) async {
    final repo = MemoryMachines();
    await open(tester, repo, {
      PermissionCodes.machineView,
      PermissionCodes.machineLog,
    });
    expect(find.text('Nhật ký ca máy'), findsOneWidget);
    expect(find.text('Giá ca máy'), findsNothing);
    expect(find.text('Xuất Excel'), findsNothing);
    expect(repo.rateReads, 0);
    expect(repo.expenseReads, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('save profile reload uses synchronous setState callback', (
    tester,
  ) async {
    final repo = MemoryMachines();
    await open(tester, repo, PermissionCodes.values.toSet());
    await tester.tap(find.text('Hồ sơ máy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(repo.profileSaves, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'rate form requires explicit shift policy currency and rounding',
    (tester) async {
      final repo = MemoryMachines();
      await open(tester, repo, PermissionCodes.values.toSet());
      await tester.tap(find.text('Giá ca máy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Chọn rõ giá trị'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
