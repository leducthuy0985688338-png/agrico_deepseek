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
  const InventoryService(this.repository);

  final InventoryRepository repository;

  void _authorize(AuthorizationSubject subject, String permission) {
    if (!subject.dataScopes.contains(DataScope.allFarm) ||
        !const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: ResourceContext(farmId: subject.farmId),
        )) {
      throw StateError('Inventory requires farm-wide access.');
    }
  }

  Future<List<InventoryItem>> list(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    return repository.listByFarm(subject.farmId);
  }

  Future<List<InventoryMovement>> movements(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    return repository.movementsByFarm(subject.farmId);
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
    return _destinations.productionDestinations(subject.farmId);
  }

  Future<List<ProductionIdentityChoice>> productionParcels(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    return _destinations.productionParcels(subject.farmId);
  }

  Future<List<ProductionSeason>> productionSeasons(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    return _destinations.productionSeasons(subject.farmId);
  }

  Future<List<ProductionMaterialCost>> productionCosts(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.financeView);
    return _destinations.productionCosts(subject.farmId);
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
    return _destinations.recordProductionIssue(
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
    _authorize(subject, PermissionCodes.inventoryManage);
    if (movement.farmId != subject.farmId) {
      throw StateError('Movement is outside the current farm.');
    }
    movement.validate();
    return repository.record(_priced(subject, movement));
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
    return _planning.productionPlans(subject.farmId);
  }

  Future<List<ProductionPlanTask>> productionPlanTasks(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    if (repository is! ProductionPlanningRepository) return Future.value([]);
    return _planning.productionPlanTasks(subject.farmId);
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
    return (store as ProductionMachineCostRepository).productionMachineCosts(
      subject.farmId,
    );
  }

  Future<List<ProductionLaborCost>> productionLaborCosts(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.financeView);
    final store = repository;
    if (store is! ProductionLaborCostRepository) return Future.value([]);
    return (store as ProductionLaborCostRepository).productionLaborCosts(
      subject.farmId,
    );
  }
}
