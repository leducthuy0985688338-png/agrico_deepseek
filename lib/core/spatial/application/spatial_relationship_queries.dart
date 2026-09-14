import '../data/spatial_relationship_repository.dart';
import '../domain/entities/spatial_relationship.dart';

/// Read-only application boundary for Spatial Core relationships.
///
/// Spatial relationships connect stable SpatialFeature identities without
/// changing either feature's identity or revision history.
class SpatialRelationshipQueries {
  const SpatialRelationshipQueries({required this.repository});

  final SpatialRelationshipRepository repository;

  /// Returns a relationship by its stable relationship id.
  Future<SpatialRelationship?> getRelationship(String relationshipId) {
    _requireId(relationshipId, 'relationshipId');
    return repository.findById(relationshipId);
  }

  /// Returns relationships originating from a SpatialFeature.
  Future<List<SpatialRelationship>> getOutgoingRelationships(
    String sourceFeatureId,
  ) async {
    _requireId(sourceFeatureId, 'sourceFeatureId');

    final relationships = await repository.findBySourceFeatureId(
      sourceFeatureId,
    );

    return List.unmodifiable(relationships);
  }

  /// Returns relationships pointing to a SpatialFeature.
  Future<List<SpatialRelationship>> getIncomingRelationships(
    String targetFeatureId,
  ) async {
    _requireId(targetFeatureId, 'targetFeatureId');

    final relationships = await repository.findByTargetFeatureId(
      targetFeatureId,
    );

    return List.unmodifiable(relationships);
  }

  /// Returns directed relationships from one feature to another.
  Future<List<SpatialRelationship>> getRelationshipsBetween(
    String sourceFeatureId,
    String targetFeatureId,
  ) async {
    _requireId(sourceFeatureId, 'sourceFeatureId');
    _requireId(targetFeatureId, 'targetFeatureId');

    final relationships = await repository.findBetweenFeatures(
      sourceFeatureId: sourceFeatureId,
      targetFeatureId: targetFeatureId,
    );

    return List.unmodifiable(relationships);
  }

  /// Returns all relationships of a specific relationship type.
  Future<List<SpatialRelationship>> getRelationshipsByType(
    String relationshipType,
  ) async {
    _requireText(relationshipType, 'relationshipType');

    final relationships = await repository.findByRelationshipType(
      relationshipType,
    );

    return List.unmodifiable(relationships);
  }

  /// Returns every persisted Spatial Core relationship.
  Future<List<SpatialRelationship>> listRelationships() async {
    final relationships = await repository.findAll();
    return List.unmodifiable(relationships);
  }

  static void _requireId(String value, String fieldName) {
    _requireText(value, fieldName);
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('$fieldName cannot be blank.');
    }
  }
}
