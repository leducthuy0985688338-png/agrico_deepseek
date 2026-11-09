import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 9, 8, 2);
  final originalBoundary = Wgs84Polygon.fromVertices(const [
    Wgs84Vertex(latitude: 16.5, longitude: 104.7),
    Wgs84Vertex(latitude: 16.5, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.7),
  ]);

  LandParcel createParcel() => LandParcel.create(
    id: 'parcel-1',
    farmId: 'farm-1',
    parcelCode: 'P-001',
    name: 'North field',
    boundary: originalBoundary,
    boundarySource: BoundarySource.gps,
    verificationStatus: BoundaryVerificationStatus.measured,
    actorMembershipId: 'member-1',
    occurredAt: capturedAt,
  );

  test('creates canonical parcel and immutable boundary version one', () {
    final parcel = createParcel();

    expect(parcel.schemaVersion, LandParcel.currentSchemaVersion);
    expect(parcel.boundaryVersion, 1);
    expect(parcel.boundaryHistory, hasLength(1));
    expect(parcel.boundaryHistory.single.version, 1);
    expect(parcel.boundaryHistory.single.source, BoundarySource.gps);
    expect(parcel.areaHa, closeTo(parcel.areaM2 / 10000, 1e-10));
    expect(() => parcel.boundaryHistory.clear(), throwsUnsupportedError);
    expect(BoundarySource.values, [
      BoundarySource.gps,
      BoundarySource.googleEarth,
      BoundarySource.manual,
      BoundarySource.cad,
      BoundarySource.imported,
    ]);
  });

  test('verified boundary cannot be silently overwritten', () {
    final verified = LandParcel.create(
      id: 'parcel-verified',
      farmId: 'farm-1',
      parcelCode: 'P-002',
      name: 'Verified field',
      boundary: originalBoundary,
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.verified,
      actorMembershipId: 'member-1',
      occurredAt: capturedAt,
    );

    expect(
      () => verified.replaceBoundary(
        boundary: originalBoundary,
        source: BoundarySource.imported,
        verificationStatus: BoundaryVerificationStatus.draft,
        actorMembershipId: 'member-2',
        occurredAt: capturedAt.add(const Duration(hours: 1)),
      ),
      throwsStateError,
    );
  });

  test('boundary replacement appends history without mutating old parcel', () {
    final parcel = createParcel();
    final replacement = Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.5, longitude: 104.7),
      Wgs84Vertex(latitude: 16.5, longitude: 104.702),
      Wgs84Vertex(latitude: 16.501, longitude: 104.702),
      Wgs84Vertex(latitude: 16.501, longitude: 104.7),
    ]);

    final updated = parcel.replaceBoundary(
      boundary: replacement,
      source: BoundarySource.googleEarth,
      verificationStatus: BoundaryVerificationStatus.draft,
      actorMembershipId: 'member-2',
      occurredAt: capturedAt.add(const Duration(hours: 1)),
      note: 'Imported correction',
      sourceFileName: 'parcel.kml',
    );

    expect(parcel.boundaryVersion, 1);
    expect(parcel.boundaryHistory, hasLength(1));
    expect(updated.boundaryVersion, 2);
    expect(updated.boundaryHistory, hasLength(2));
    expect(updated.boundaryHistory.last.source, BoundarySource.googleEarth);
    expect(updated.boundaryHistory.last.sourceFileName, 'parcel.kml');
  });

  test('restoring history creates a new version instead of rewriting it', () {
    final parcel = createParcel();
    final changed = parcel.replaceBoundary(
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.702),
        Wgs84Vertex(latitude: 16.501, longitude: 104.7),
      ]),
      source: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-1',
      occurredAt: capturedAt.add(const Duration(hours: 1)),
    );

    final restored = changed.restoreBoundaryVersion(
      version: 1,
      actorMembershipId: 'member-1',
      occurredAt: capturedAt.add(const Duration(hours: 2)),
    );

    expect(restored.boundaryVersion, 3);
    expect(restored.boundaryHistory.map((item) => item.version), [1, 2, 3]);
    expect(restored.boundary, originalBoundary);
    expect(restored.boundaryHistory.last.note, 'Restored from version 1');
  });
}
