import '../domain/entities/spatial_temporal_record.dart';

abstract interface class SpatialTemporalRepository {
  Future<SpatialTemporalRecord?> findById(String id);

  Future<List<SpatialTemporalRecord>> findBySpatialFeatureId(
    String spatialFeatureId,
  );

  Future<List<SpatialTemporalRecord>> findByState(SpatialTemporalState state);

  Future<List<SpatialTemporalRecord>> findBetweenDates({
    required DateTime from,
    required DateTime to,
  });

  Future<List<SpatialTemporalRecord>> findAll();

  Future<void> create(SpatialTemporalRecord record);
}
