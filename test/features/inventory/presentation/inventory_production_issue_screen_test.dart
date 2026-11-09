import 'package:agrico_deepseek/features/inventory/domain/repositories/production_planning_repository.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/inventory/application/inventory_service.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:agrico_deepseek/features/inventory/domain/repositories/production_destination_repository.dart';
import 'package:agrico_deepseek/features/inventory/presentation/inventory_catalog_screen.dart';
import 'package:agrico_deepseek/features/inventory/presentation/production_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// UI behavior uses a memory repository; real SQLite transaction and cleanup
// behavior is exercised separately by production_destination_test and migration tests.
class _Inventory
    implements
        InventoryRepository,
        ProductionDestinationRepository,
        ProductionPlanningRepository {
  final seasons = <ProductionSeason>[];
  final posted = <Map<String, Object?>>[];
  num stock = 10;
  int costReads = 0;
  final costRows = <ProductionMaterialCost>[];
  @override
  Future<List<InventoryItem>> listByFarm(String farmId) async => [
    InventoryItem(
      id: 'item',
      farmId: farmId,
      code: 'VT001',
      name: 'Material',
      unit: 'kg',
      unitPrice: 10,
      supplier: '',
      stock: stock,
    ),
  ];
  @override
  Future<void> register(InventoryItem item) async => throw UnimplementedError();
  @override
  Future<void> record(InventoryMovement movement) async =>
      throw UnimplementedError();
  @override
  Future<List<InventoryMovement>> movementsByFarm(String farmId) async => [];
  @override
  Future<List<ProductionIdentityChoice>> productionParcels(
    String farmId,
  ) async => const [
    ProductionIdentityChoice('p1', 'P001'),
    ProductionIdentityChoice('p2', 'P002'),
  ];
  @override
  Future<List<ProductionSeason>> productionSeasons(String farmId) async =>
      List.of(seasons);
  @override
  Future<void> createProductionSeason(ProductionSeason season) async {
    seasons.add(season);
  }

  @override
  Future<void> setProductionSeasonActive(
    String farmId,
    String seasonId,
    bool active,
  ) async {
    final i = seasons.indexWhere((s) => s.id == seasonId);
    final s = seasons[i];
    seasons[i] = ProductionSeason(
      id: s.id,
      farmId: s.farmId,
      parcelId: s.parcelId,
      name: s.name,
      startsOn: s.startsOn,
      active: active,
    );
  }

  @override
  Future<List<ProductionDestination>> productionDestinations(
    String farmId,
  ) async => [
    for (final s in seasons.where((s) => s.active))
      ProductionDestination(
        parcelId: s.parcelId,
        parcelCode: s.parcelId == 'p1' ? 'P001' : 'P002',
        seasonId: s.id,
        seasonName: s.name,
      ),
  ];
  @override
  Future<void> recordProductionIssue(
    InventoryMovement movement, {
    required String parcelId,
    required String seasonId,
    String? planId,
  }) async {
    posted.add({
      'parcel_id': parcelId,
      'season_id': seasonId,
      'quantity': movement.quantity,
    });
    stock -= movement.quantity;
  }

  @override
  Future<List<ProductionMaterialCost>> productionCosts(String farmId) async {
    costReads++;
    return List.of(costRows);
  }

  @override
  Future<List<ProductionPlan>> productionPlans(String farmId) async => [
    for (final s in seasons)
      ProductionPlan(
        id: 'plan-${s.id}',
        farmId: farmId,
        parcelId: s.parcelId,
        seasonId: s.id,
        name: 'Plan ${s.id}',
        crop: 'Peanut',
        startsOn: '2026-01-01',
        endsOn: '2099-12-31',
        currency: 'VND',
        materialBudget: '100',
        laborBudget: '0',
        machineBudget: '0',
        laborHours: '0',
        machineShifts: '0',
        code: 'KH-${s.id}',
        status: ProductionPlanStatus.active,
      ),
  ];
  @override
  Future<List<ProductionPlanTask>> productionPlanTasks(String farmId) async =>
      [];
  @override
  Future<void> createProductionPlan(ProductionPlan p, String actor) async =>
      throw UnimplementedError();
  @override
  Future<void> changeProductionPlanStatus(
    String farm,
    String id,
    int rev,
    ProductionPlanStatus status,
    String actor,
  ) async => throw UnimplementedError();
  @override
  Future<void> createProductionPlanTask(
    ProductionPlanTask t,
    String actor,
  ) async => throw UnimplementedError();
  @override
  Future<void> completeProductionPlanTask(
    String farm,
    String id,
    int rev,
    bool done,
    String actor,
  ) async => throw UnimplementedError();
}

void main() {
  late _Inventory repo;
  const subject = AuthorizationSubject(
    userId: 'admin',
    membershipId: 'member',
    farmId: 'farm',
    permissionCodes: {
      PermissionCodes.inventoryView,
      PermissionCodes.inventoryManage,
      PermissionCodes.inventoryPrice,
      PermissionCodes.productionPlan,
      PermissionCodes.financeView,
    },
    dataScopes: {DataScope.allFarm},
  );
  setUp(() => repo = _Inventory());
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
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
        home: InventoryCatalogScreen(
          subject: subject,
          service: InventoryService(repo, currentSubject: () => subject),
          productionIssuesEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, Finder picker, String label) async {
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'V2 production picker resets season and submits only the chosen parcel',
    (tester) async {
      for (final i in [1, 2]) {
        repo.seasons.add(
          ProductionSeason(
            id: 's$i',
            farmId: 'farm',
            parcelId: 'p$i',
            name: 'Season $i',
            startsOn: '2026-01-01',
          ),
        );
      }
      await open(tester);
      await tester.tap(
        find.byKey(const Key('inventory-production-issue-item')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('inventory-movement-quantity')),
        '2',
      );
      await tester.tap(find.byKey(const Key('inventory-movement-save')));
      await tester.pump();
      expect(repo.posted, isEmpty);
      expect(find.byKey(const Key('inventory-movement-error')), findsOneWidget);
      await select(
        tester,
        find.byKey(const Key('inventory-production-parcel')),
        'P001',
      );
      await select(
        tester,
        find.byKey(const ValueKey('inventory-production-season-p1')),
        'Season 1',
      );
      await select(
        tester,
        find.byKey(const Key('inventory-production-parcel')),
        'P002',
      );
      expect(find.text('Season 1'), findsNothing);
      await tester.tap(find.byKey(const Key('inventory-movement-save')));
      await tester.pump();
      expect(repo.posted, isEmpty);
      await select(
        tester,
        find.byKey(const ValueKey('inventory-production-season-p2')),
        'Season 2',
      );
      await select(
        tester,
        find.byKey(const ValueKey('inventory-production-plan-s2')),
        'KH-s2 · Plan s2 (VND)',
      );
      await tester.enterText(
        find.byKey(const Key('inventory-movement-price')),
        '10',
      );

      await tester.tap(find.byKey(const Key('inventory-movement-save')));
      await tester.pumpAndSettle();
      expect(repo.posted.single, {
        'parcel_id': 'p2',
        'season_id': 's2',
        'quantity': 2,
      });
      expect(repo.stock, 8);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'creates season directly on a V2 plot without any legacy field selection',
    (tester) async {
      await open(tester);
      expect(find.byKey(const Key('inventory-link-production')), findsNothing);
      expect(find.byKey(const Key('inventory-retry-cost-sync')), findsNothing);
      await tester.tap(find.byKey(const Key('inventory-production-workspace')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('production-add-season')));
      await tester.pumpAndSettle();
      await select(
        tester,
        find.byKey(const Key('production-season-parcel')),
        'P001',
      );
      await tester.enterText(
        find.byKey(const Key('production-season-name')),
        'Peanut 2026',
      );
      await tester.tap(find.byKey(const Key('production-season-save')));
      await tester.pumpAndSettle();
      expect(repo.seasons.single.parcelId, 'p1');
      expect(repo.seasons.single.name, 'Peanut 2026');
      final id = repo.seasons.single.id;
      await tester.tap(find.byKey(Key('production-toggle-$id')));
      await tester.pumpAndSettle();
      expect(repo.seasons.single.active, isFalse);
      expect(await repo.productionDestinations('farm'), isEmpty);
      expect(repo.posted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'no seasons blocks production issue and directs user to the V2 workspace',
    (tester) async {
      await open(tester);
      await tester.tap(
        find.byKey(const Key('inventory-production-issue-item')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Mở Mùa vụ'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('inventory-movement-quantity')),
        '2',
      );
      await tester.tap(find.byKey(const Key('inventory-movement-save')));
      await tester.pump();
      expect(repo.posted, isEmpty);
      expect(repo.stock, 10);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cost screen respects the selected V2 plot', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final i in [1, 2]) {
      repo.seasons.add(
        ProductionSeason(
          id: 's$i',
          farmId: 'farm',
          parcelId: 'p$i',
          name: 'Season $i',
          startsOn: '2026-01-01',
        ),
      );
      repo.costRows.add(
        ProductionMaterialCost(
          movementId: 'm$i',
          parcelId: 'p$i',
          parcelCode: 'P00$i',
          seasonId: 's$i',
          seasonName: 'Season $i',
          itemName: 'Material $i',
          unit: 'kg',
          quantity: 2,
          unitPrice: 12,
          amount: 24,
          occurredAt: DateTime.utc(2026, 10, 25),
        ),
      );
    }
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
        home: ProductionWorkspaceScreen(
          service: InventoryService(repo, currentSubject: () => subject),
          subject: subject,
          initialParcelId: 'p1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Material 1'), findsOneWidget);
    expect(find.textContaining('Material 2'), findsNothing);
    expect(find.text('Season 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inventory viewer cannot plan seasons or read financial material costs',
    (tester) async {
      const viewer = AuthorizationSubject(
        userId: 'v',
        membershipId: 'm',
        farmId: 'farm',
        permissionCodes: {PermissionCodes.inventoryView},
        dataScopes: {DataScope.allFarm},
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
          home: ProductionWorkspaceScreen(
            service: InventoryService(repo, currentSubject: () => viewer),
            subject: viewer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('production-add-season')), findsNothing);
      expect(repo.costReads, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
