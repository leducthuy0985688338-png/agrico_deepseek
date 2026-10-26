import '../../../core/permissions/operation_scope.dart';
import '../domain/repositories/warehouse_repository.dart';
import '../../../core/permissions/live_authorization.dart';
import '../../machines/domain/machines.dart'
    show ProductionMachineCost, ProductionMachineCostRepository;
import '../../personnel/domain/personnel.dart'
    show ProductionLaborCost, ProductionLaborCostRepository;
import '../domain/repositories/production_planning_repository.dart';
import '../domain/entities/exact_decimal.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/entities/inventory_item.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/production_destination_repository.dart';

class InventoryService {
  const InventoryService(this.repository, {required this.currentSubject});
  final AuthorizationSubject? Function() currentSubject;
  LiveAuthorization get access => LiveAuthorization(currentSubject);

  final InventoryRepository repository;

  bool canOpenWarehouse(AuthorizationSubject s) =>
      access.canEnter(s, PermissionCodes.inventoryView);
  bool canAtWarehouse(AuthorizationSubject s, String p, String id) =>
      access.can(
        s,
        p,
        resource: ResourceContext(farmId: s.farmId, warehouseId: id),
      );
  String warehouseOf(AuthorizationSubject s, String? id) =>
      id ?? InventoryWarehouse.defaultId(s.farmId);
  Future<List<InventoryWarehouse>> warehouses(AuthorizationSubject s) {
    if (!canOpenWarehouse(s)) throw StateError('Warehouse access denied.');
    final r = repository;
    if (r is! WarehouseRepository) return Future.value([]);
    return access.readScoped(
      s,
      [PermissionCodes.inventoryView],
      () => (r as WarehouseRepository).warehouses(
        s.farmId,
        OperationScope(s, access, [PermissionCodes.inventoryView]),
      ),
    );
  }

  Future<void> createWarehouse(AuthorizationSubject s, String id, String name) {
    access.require(s, PermissionCodes.catalogManage);
    return (repository as WarehouseRepository).createWarehouse(
      s.farmId,
      id,
      name,
      s.userId,
    );
  }

  Future<void> transfer(
    AuthorizationSubject s, {
    required String id,
    required String itemId,
    required String sourceId,
    required String destinationId,
    required num quantity,
    required DateTime at,
  }) {
    final scope = OperationScope(s, access, [
      PermissionCodes.inventoryView,
      PermissionCodes.inventoryTransfer,
    ]);
    scope.require(ResourceContext(farmId: s.farmId, warehouseId: sourceId));
    scope.require(
      ResourceContext(farmId: s.farmId, warehouseId: destinationId),
    );
    return (repository as WarehouseRepository).transfer(
      s.farmId,
      id,
      itemId,
      sourceId,
      destinationId,
      quantity,
      at,
      s.userId,
      scope,
    );
  }

  InventoryRepository warehouseStore(
    AuthorizationSubject s,
    String? id,
    List<String> permissions,
  ) {
    if (id == null) {
      for (final p in permissions) {
        access.require(s, p);
      }
      return repository;
    }
    final r = repository;
    final scope = OperationScope(s, access, permissions);
    scope.require(ResourceContext(farmId: s.farmId, warehouseId: id));
    if (r is! WarehouseRepository)
      throw StateError('Warehouse repository unavailable.');
    return (r as WarehouseRepository).inWarehouse(scope, id);
  }

  bool can(AuthorizationSubject subject, String permission) =>
      access.can(subject, permission);
  void _authorize(AuthorizationSubject subject, String permission) {
    access.require(subject, permission);
  }

  void exportPermission(AuthorizationSubject subject, {String? warehouseId}) {
    for (final permission in [
      PermissionCodes.inventoryView,
      PermissionCodes.reportOperations,
      PermissionCodes.dataExport,
    ]) {
      if (warehouseId == null) {
        _authorize(subject, permission);
      } else if (!canAtWarehouse(subject, permission, warehouseId)) {
        throw StateError('Warehouse export denied.');
      }
    }
  }

  Future<List<InventoryItem>> list(
    AuthorizationSubject subject, {
    String? warehouseId,
  }) {
    final r = warehouseStore(subject, warehouseId, [
      PermissionCodes.inventoryView,
    ]);
    return access.readScoped(subject, [
      PermissionCodes.inventoryView,
    ], () => r.listByFarm(subject.farmId));
  }

  Future<List<InventoryMovement>> movements(
    AuthorizationSubject subject, {
    String? warehouseId,
  }) {
    final r = warehouseStore(subject, warehouseId, [
      PermissionCodes.inventoryView,
    ]);
    return access.readScoped(subject, [
      PermissionCodes.inventoryView,
    ], () => r.movementsByFarm(subject.farmId));
  }

  Future<void> register(AuthorizationSubject subject, InventoryItem item) {
    _authorize(subject, PermissionCodes.catalogManage);
    if (item.farmId != subject.farmId) {
      throw StateError('Item is outside the current farm.');
    }
    item.validate();
    return repository.register(item);
  }

  ProductionDestinationRepository get _destinations {
    final store = repository;
    if (store is! ProductionDestinationRepository) {
      throw StateError('Production destinations are unavailable.');
    }
    return store as ProductionDestinationRepository;
  }

  Future<List<ProductionDestination>> productionDestinations(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryManage);
    return access.read(subject, [
      PermissionCodes.inventoryManage,
    ], () => _destinations.productionDestinations(subject.farmId));
  }

  Future<List<ProductionIdentityChoice>> productionParcels(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    return access.read(subject, [
      PermissionCodes.inventoryView,
    ], () => _destinations.productionParcels(subject.farmId));
  }

  Future<List<ProductionSeason>> productionSeasons(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    return access.read(subject, [
      PermissionCodes.inventoryView,
    ], () => _destinations.productionSeasons(subject.farmId));
  }

  Future<List<ProductionMaterialCost>> productionCosts(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.financeView);
    return access.read(subject, [
      PermissionCodes.financeView,
    ], () => _destinations.productionCosts(subject.farmId));
  }

  Future<void> createProductionSeason(
    AuthorizationSubject subject,
    ProductionSeason season,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    if (season.farmId != subject.farmId) {
      throw StateError('Season is outside this farm.');
    }
    season.validate();
    return _destinations.createProductionSeason(season);
  }

  Future<void> setProductionSeasonActive(
    AuthorizationSubject subject,
    String seasonId,
    bool active,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    return _destinations.setProductionSeasonActive(
      subject.farmId,
      seasonId,
      active,
    );
  }

  /// Production issues require an explicit destination and a SQLite-backed
  /// repository whose contract commits stock and production cost atomically.
  Future<void> recordProductionIssue(
    AuthorizationSubject subject,
    InventoryMovement movement, {
    required String parcelId,
    required String seasonId,
    String? planId,
  }) {
    _authorize(subject, PermissionCodes.inventoryManage);
    if (movement.farmId != subject.farmId) {
      throw StateError('Movement is outside the current farm.');
    }
    movement.validate();
    final store = repository is WarehouseRepository
        ? warehouseStore(subject, warehouseOf(subject, movement.warehouseId), [
                PermissionCodes.inventoryView,
                PermissionCodes.inventoryManage,
                PermissionCodes.inventoryPrice,
              ])
              as ProductionDestinationRepository
        : _destinations;
    return store.recordProductionIssue(
      _priced(subject, movement),
      planId: planId,
      parcelId: parcelId,
      seasonId: seasonId,
    );
  }

  Future<void> record(
    AuthorizationSubject subject,
    InventoryMovement movement,
  ) {
    if (movement.farmId != subject.farmId) throw StateError('Wrong farm.');
    movement.validate();
    final selected = warehouseOf(subject, movement.warehouseId);
    final permission =
        canAtWarehouse(subject, PermissionCodes.inventoryManage, selected)
        ? PermissionCodes.inventoryManage
        : movement.kind == InventoryMovementKind.receipt
        ? PermissionCodes.inventoryReceive
        : PermissionCodes.inventoryIssue;
    if (repository is! WarehouseRepository) {
      _authorize(subject, PermissionCodes.inventoryManage);
      return repository.record(_priced(subject, movement));
    }
    return warehouseStore(subject, selected, [
      PermissionCodes.inventoryView,
      permission,
      if (movement.unitPriceText != null ||
          movement.kind == InventoryMovementKind.issue)
        PermissionCodes.inventoryPrice,
    ]).record(_priced(subject, movement));
  }

  InventoryMovement _priced(
    AuthorizationSubject subject,
    InventoryMovement movement,
  ) {
    if (movement.kind == InventoryMovementKind.issue ||
        movement.unitPriceText != null) {
      _authorize(subject, PermissionCodes.inventoryPrice);
      ExactDecimal.validatePrice(
        movement.unitPriceText ?? '',
        movement.currency ?? '',
      );
      if (ExactDecimal.parse(movement.unitPriceText!).coefficient ==
              BigInt.zero &&
          !movement.zeroPriceConfirmed) {
        throw const FormatException('Zero price must be explicitly confirmed.');
      }
      return movement.withPricedBy(subject.userId);
    }
    return movement;
  }

  ProductionPlanningRepository get _planning {
    final store = repository;
    if (store is! ProductionPlanningRepository) {
      throw StateError('Planning unavailable.');
    }
    return store as ProductionPlanningRepository;
  }

  Future<List<ProductionPlan>> productionPlans(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    _authorize(subject, PermissionCodes.financeView);
    if (repository is! ProductionPlanningRepository) return Future.value([]);
    return access.read(subject, [
      PermissionCodes.inventoryView,
      PermissionCodes.financeView,
    ], () => _planning.productionPlans(subject.farmId));
  }

  Future<List<ProductionPlanTask>> productionPlanTasks(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    if (repository is! ProductionPlanningRepository) return Future.value([]);
    return access.read(subject, [
      PermissionCodes.inventoryView,
    ], () => _planning.productionPlanTasks(subject.farmId));
  }

  Future<void> createProductionPlan(
    AuthorizationSubject subject,
    ProductionPlan plan,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    _authorize(subject, PermissionCodes.financeView);
    if (plan.farmId != subject.farmId) throw StateError('Plan outside farm.');
    plan.validate();
    return _planning.createProductionPlan(plan, subject.userId);
  }

  Future<void> changeProductionPlanStatus(
    AuthorizationSubject subject,
    ProductionPlan plan,
    ProductionPlanStatus status,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    if (plan.farmId != subject.farmId) throw StateError('Plan outside farm.');
    return _planning.changeProductionPlanStatus(
      subject.farmId,
      plan.id,
      plan.revision,
      status,
      subject.userId,
    );
  }

  Future<void> createProductionPlanTask(
    AuthorizationSubject subject,
    ProductionPlanTask task,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    _authorize(subject, PermissionCodes.taskCreate);
    if (task.farmId != subject.farmId) throw StateError('Task outside farm.');
    task.validate();
    return _planning.createProductionPlanTask(task, subject.userId);
  }

  Future<void> completeProductionPlanTask(
    AuthorizationSubject subject,
    ProductionPlanTask task,
    bool completed,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    _authorize(
      subject,
      completed ? PermissionCodes.taskComplete : PermissionCodes.taskEdit,
    );
    if (task.farmId != subject.farmId) throw StateError('Task outside farm.');
    return _planning.completeProductionPlanTask(
      subject.farmId,
      task.id,
      task.revision,
      completed,
      subject.userId,
    );
  }

  Future<List<ProductionMachineCost>> productionMachineCosts(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.financeView);
    final store = repository;
    if (store is! ProductionMachineCostRepository) return Future.value([]);
    return access.read(
      subject,
      [PermissionCodes.financeView],
      () => (store as ProductionMachineCostRepository).productionMachineCosts(
        subject.farmId,
      ),
    );
  }

  Future<List<ProductionLaborCost>> productionLaborCosts(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.financeView);
    final store = repository;
    if (store is! ProductionLaborCostRepository) return Future.value([]);
    return access.read(
      subject,
      [PermissionCodes.financeView],
      () => (store as ProductionLaborCostRepository).productionLaborCosts(
        subject.farmId,
      ),
    );
  }
}
