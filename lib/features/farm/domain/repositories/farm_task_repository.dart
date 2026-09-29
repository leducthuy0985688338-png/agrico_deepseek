import '../entities/farm_task.dart';

abstract interface class FarmTaskRepository {
  Future<void> create(FarmTask task);
  Future<List<FarmTask>> listByFarm(String farmId);
  Future<void> complete({required String farmId, required String id});
}
