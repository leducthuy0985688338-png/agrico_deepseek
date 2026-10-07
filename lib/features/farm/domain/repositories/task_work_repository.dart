import '../entities/parcel_work.dart';

abstract interface class TaskWorkRepository {
  /// Creates a new event and its task link atomically; never changes task status.
  Future<void> record(String taskId, ParcelWorkEvent event);
  Future<List<ParcelWorkEvent>> events(String farmId, String taskId);
}
