import '../entities/production_plan.dart';
export '../entities/production_plan.dart';

abstract interface class ProductionPlanningRepository {
  Future<List<ProductionPlan>> productionPlans(String farmId);
  Future<void> createProductionPlan(ProductionPlan plan, String actorId);
  Future<void> changeProductionPlanStatus(
    String farmId,
    String planId,
    int revision,
    ProductionPlanStatus status,
    String actorId,
  );
  Future<List<ProductionPlanTask>> productionPlanTasks(String farmId);
  Future<void> createProductionPlanTask(
    ProductionPlanTask task,
    String actorId,
  );
  Future<void> completeProductionPlanTask(
    String farmId,
    String taskId,
    int revision,
    bool completed,
    String actorId,
  );
}
