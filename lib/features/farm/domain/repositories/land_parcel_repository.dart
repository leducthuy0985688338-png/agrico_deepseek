import '../entities/land_parcel.dart';

abstract interface class LandParcelRepository {
  Future<LandParcel?> getById({required String farmId, required String id});

  Future<LandParcel?> getByParcelCode({
    required String farmId,
    required String parcelCode,
  });

  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  });

  /// Persists the parcel and its initial immutable history atomically.
  Future<void> create(LandParcel parcel);

  /// Persists current parcel state and any new boundary versions atomically.
  Future<void> update(LandParcel parcel);

  Future<void> saveBoundaryVersion(LandParcelBoundaryVersion version);

  /// Soft deletion keeps boundary audit history intact.
  Future<void> setActive({
    required String farmId,
    required String id,
    required bool active,
    required String actorMembershipId,
    required DateTime occurredAt,
  });

  /// All calls made on the scoped repository commit or roll back together.
  Future<T> transaction<T>(
    Future<T> Function(LandParcelRepository repository) action,
  );
}
