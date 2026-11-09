import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LandParcelSpatialLink link({
    String id = 'link-1',
    String landParcelId = 'parcel-1',
    String spatialFeatureId = 'spatial-1',
    String createdBy = 'member-1',
    int schemaVersion = LandParcelSpatialLink.currentSchemaVersion,
  }) {
    return LandParcelSpatialLink(
      id: id,
      landParcelId: landParcelId,
      spatialFeatureId: spatialFeatureId,
      createdAt: DateTime.utc(2026, 9, 11, 8),
      createdBy: createdBy,
      schemaVersion: schemaVersion,
    );
  }

  test('valid stable primary link passes validation', () {
    final value = link();

    expect(() => value.validate(), returnsNormally);
    expect(value.landParcelId, 'parcel-1');
    expect(value.spatialFeatureId, 'spatial-1');
    expect(value.schemaVersion, LandParcelSpatialLink.currentSchemaVersion);
  });

  test('LandParcel and SpatialFeature retain independent identities', () {
    final value = link(
      landParcelId: 'parcel-business-id',
      spatialFeatureId: 'spatial-gis-id',
    );

    value.validate();

    expect(value.landParcelId, isNot(value.spatialFeatureId));
  });

  test('blank link id is rejected', () {
    expect(() => link(id: ' ').validate(), throwsFormatException);
  });

  test('blank LandParcel id is rejected', () {
    expect(() => link(landParcelId: ' ').validate(), throwsFormatException);
  });

  test('blank SpatialFeature id is rejected', () {
    expect(() => link(spatialFeatureId: ' ').validate(), throwsFormatException);
  });

  test('blank creator is rejected', () {
    expect(() => link(createdBy: ' ').validate(), throwsFormatException);
  });

  test('non-positive schema version is rejected', () {
    expect(() => link(schemaVersion: 0).validate(), throwsFormatException);
  });
}
