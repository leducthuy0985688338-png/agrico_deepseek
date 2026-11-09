import '../entities/parcel_land_history.dart';

abstract interface class ParcelLandHistoryRepository {
  Future<void> capture(ParcelStageSnapshot snapshot);
  Future<List<ParcelStageSnapshot>> snapshots(String farmId, String parcelId);
  Future<void> link(ParcelDerivation derivation);
  Future<List<ParcelDerivation>> derivations(String farmId, String parcelId);
}
