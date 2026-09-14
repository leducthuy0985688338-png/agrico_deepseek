import '../data/spatial_temporal_repository.dart';
import '../domain/entities/spatial_temporal_record.dart';

/// Read-only application boundary for Spatial Core temporal history.
///
/// Temporal history preserves the sequence of BEFORE -> CHANGE -> AFTER
/// states for a stable SpatialFeature identity.
///
/// This boundary contains no persistence logic, UI logic, or mutation
/// operations.
class SpatialTemporalQueries {
  const SpatialTemporalQueries({required this.repository});

  final SpatialTemporalRepository repository;

  Future<SpatialTemporalRecord?> getRecord(String recordId) {
    _requireText(recordId, 'recordId');
    return repository.findById(recordId);
  }

  Future<List<SpatialTemporalRecord>> getFeatureHistory(
    String spatialFeatureId,
  ) async {
    _requireText(spatialFeatureId, 'spatialFeatureId');

    final records = await repository.findBySpatialFeatureId(spatialFeatureId);

    final ordered = List<SpatialTemporalRecord>.of(records)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return List.unmodifiable(ordered);
  }

  Future<List<SpatialTemporalRecord>> getRecordsByState(
    SpatialTemporalState state,
  ) async {
    final records = await repository.findByState(state);

    final ordered = List<SpatialTemporalRecord>.of(records)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return List.unmodifiable(ordered);
  }

  Future<List<SpatialTemporalRecord>> getRecordsBetweenDates({
    required DateTime from,
    required DateTime to,
  }) async {
    if (from.isAfter(to)) {
      throw const FormatException(
        'The start date cannot be after the end date.',
      );
    }

    final records = await repository.findBetweenDates(from: from, to: to);

    final ordered = List<SpatialTemporalRecord>.of(records)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return List.unmodifiable(ordered);
  }

  Future<List<SpatialTemporalRecord>> listRecords() async {
    final records = await repository.findAll();

    final ordered = List<SpatialTemporalRecord>.of(records)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return List.unmodifiable(ordered);
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('$fieldName cannot be blank.');
    }
  }
}
