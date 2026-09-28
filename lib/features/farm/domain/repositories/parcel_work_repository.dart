import '../entities/parcel_work.dart';

abstract interface class ParcelWorkRepository {
  Future<void> register(WorkResource resource);
  Future<List<WorkResource>> resources(String farmId);
  Future<void> record(ParcelWorkEvent event);
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId);
}
