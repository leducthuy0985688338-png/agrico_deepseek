import '../entities/farm_task.dart';

abstract interface class FarmTaskRepository {
  Future<void> create(FarmTask task);
  Future<void> update(FarmTask task);
  Future<void> changeStatus({required String farmId, required String id,
    required FarmTaskStatus status});
  Future<List<FarmTask>> listByFarm(String farmId);
  Future<void> complete({required String farmId, required String id});
}
