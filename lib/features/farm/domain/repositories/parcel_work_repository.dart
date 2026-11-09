import '../entities/parcel_work.dart';

abstract interface class ParcelWorkRepository {
  Future<void> register(WorkResource resource);

  /// Insert all verified resources, or none if any identity is already used.
  Future<void> registerBatch(List<WorkResource> resources);
  Future<List<WorkResource>> resources(String farmId);
  Future<void> record(ParcelWorkEvent event);
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId);
}
