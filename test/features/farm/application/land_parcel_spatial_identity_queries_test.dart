import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_identity_queries.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel_spatial_link.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_spatial_link_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLandParcelSpatialLinkRepository
    implements LandParcelSpatialLinkRepository {
  final Map<String, LandParcelSpatialLink> links = {};

  @override
  Future<LandParcelSpatialLink?> findById(String id) async => links[id];

  @override
  Future<LandParcelSpatialLink?> findByLandParcelId(String landParcelId) async {
    for (final link in links.values) {
      if (link.landParcelId == landParcelId) {
        return link;
      }
    }
    return null;
  }

  @override
  Future<LandParcelSpatialLink?> findBySpatialFeatureId(
    String spatialFeatureId,
  ) async {
    for (final link in links.values) {
      if (link.spatialFeatureId == spatialFeatureId) {
        return link;
      }
    }
    return null;
  }

  @override
  Future<void> create(LandParcelSpatialLink link) async {
    links[link.id] = link;
  }
}

LandParcelSpatialLink _link({
  String id = 'link-1',
  String landParcelId = 'parcel-1',
  String spatialFeatureId = 'spatial-1',
}) {
  return LandParcelSpatialLink(
    id: id,
    landParcelId: landParcelId,
    spatialFeatureId: spatialFeatureId,
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'user-1',
  );
}

LandParcelSpatialIdentityQueries _queries({
  _FakeLandParcelSpatialLinkRepository? linkRepository,
}) {
  return LandParcelSpatialIdentityQueries(
    linkRepository: linkRepository ?? _FakeLandParcelSpatialLinkRepository(),
  );
}

void main() {
  group('LandParcelSpatialIdentityQueries', () {
    test('resolves LandParcel to stable SpatialFeature identity', () async {
      final linkRepository = _FakeLandParcelSpatialLinkRepository();

      await linkRepository.create(
        _link(landParcelId: 'parcel-123', spatialFeatureId: 'spatial-456'),
      );

      final queries = _queries(linkRepository: linkRepository);

      final result = await queries.getLandParcelSpatialIdentity('parcel-123');

      expect(result, isNotNull);
      expect(result!.landParcelId, 'parcel-123');
      expect(result.spatialFeatureId, 'spatial-456');
    });

    test('returns null when LandParcel has no spatial link', () async {
      final queries = _queries();

      final result = await queries.getLandParcelSpatialIdentity(
        'parcel-missing',
      );

      expect(result, isNull);
    });

    test('rejects blank LandParcel id', () {
      final queries = _queries();

      expect(
        () => queries.getLandParcelSpatialIdentity('   '),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
