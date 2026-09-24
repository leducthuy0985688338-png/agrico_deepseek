import '../entities/spatial_relationship.dart';

abstract interface class SpatialRelationshipRepository {
  Future<SpatialRelationship?> findById(String id);

  Future<List<SpatialRelationship>> findBySourceFeatureId(
    String sourceFeatureId,
  );

  Future<List<SpatialRelationship>> findByTargetFeatureId(
    String targetFeatureId,
  );

  Future<List<SpatialRelationship>> findBetweenFeatures({
    required String sourceFeatureId,
    required String targetFeatureId,
  });

  Future<List<SpatialRelationship>> findByRelationshipType(
    String relationshipType,
  );

  Future<List<SpatialRelationship>> findAll();

  Future<void> create(SpatialRelationship relationship);
}
