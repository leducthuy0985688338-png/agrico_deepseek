import 'package:agrico_deepseek/features/farm/data/models/land_parcel_mapper.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 9, 8, 2);
  final boundary = Wgs84Polygon.fromVertices(const [
    Wgs84Vertex(latitude: 16.5, longitude: 104.7),
    Wgs84Vertex(latitude: 16.5, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.701),
    Wgs84Vertex(latitude: 16.501, longitude: 104.7),
  ]);

  // ============================================================
  // LandParcel contract alignment
  // ============================================================
  group('LandParcel contract alignment', () {
    test('1. valid LandParcel accepts spatialFeatureId', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        spatialFeatureId: 'SPF-LP-000123',
      );

      expect(parcel.spatialFeatureId, 'SPF-LP-000123');
    });

    test('2. spatialFeatureId cannot be blank when provided', () {
      expect(
        () => LandParcel.create(
          id: 'parcel-1',
          farmId: 'farm-1',
          parcelCode: 'P-001',
          name: 'Field A',
          boundary: boundary,
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: capturedAt,
          spatialFeatureId: '   ',
        ),
        throwsFormatException,
      );
    });

    test('3. administrative codes are preserved', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        countryCode: 'LA',
        provinceCode: 'SVK',
        districtCode: 'NONG',
        villageCode: 'TAKO',
      );

      expect(parcel.countryCode, 'LA');
      expect(parcel.provinceCode, 'SVK');
      expect(parcel.districtCode, 'NONG');
      expect(parcel.villageCode, 'TAKO');
    });

    test('4. ownerHouseholdId remains compatible', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        ownerHouseholdId: 'HH-001',
      );

      expect(parcel.ownerHouseholdId, 'HH-001');
    });

    test('5. ownerDisplayName remains compatible', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        ownerDisplayName: 'Nguyễn Văn Thùy',
      );

      expect(parcel.ownerDisplayName, 'Nguyễn Văn Thùy');
    });

    test('6. ownerContact supports optional value', () {
      final withContact = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        ownerContact: '+856 20 12345678',
      );

      expect(withContact.ownerContact, '+856 20 12345678');

      final withoutContact = LandParcel.create(
        id: 'parcel-2',
        farmId: 'farm-1',
        parcelCode: 'P-002',
        name: 'Field B',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
      );

      expect(withoutContact.ownerContact, isNull);
    });

    test('7. Vietnamese owner name accepted', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Thửa đất Việt',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        ownerDisplayName: 'Nguyễn Văn Thùy',
      );

      expect(parcel.ownerDisplayName, 'Nguyễn Văn Thùy');
      expect(parcel.name, 'Thửa đất Việt');
    });

    test('8. Lao owner name accepted', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'ດິນນາ',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        ownerDisplayName: 'ນາງ ສີດາ',
        villageCode: 'TAKO',
      );

      expect(parcel.ownerDisplayName, 'ນາງ ສີດາ');
      expect(parcel.name, 'ດິນນາ');
    });

    test('9. LandParcel.id remains stable across boundary replacement', () {
      final original = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        spatialFeatureId: 'SPF-LP-000123',
      );

      final replacement = Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.702),
        Wgs84Vertex(latitude: 16.501, longitude: 104.702),
        Wgs84Vertex(latitude: 16.501, longitude: 104.7),
      ]);

      final updated = original.replaceBoundary(
        boundary: replacement,
        source: BoundarySource.googleEarth,
        verificationStatus: BoundaryVerificationStatus.draft,
        actorMembershipId: 'member-2',
        occurredAt: capturedAt.add(const Duration(hours: 1)),
      );

      expect(updated.id, original.id);
      expect(updated.id, 'parcel-1');
    });

    test(
      '10. spatialFeatureId remains stable across boundary replacement',
      () {
        final original = LandParcel.create(
          id: 'parcel-1',
          farmId: 'farm-1',
          parcelCode: 'P-001',
          name: 'Field A',
          boundary: boundary,
          boundarySource: BoundarySource.gps,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: 'member-1',
          occurredAt: capturedAt,
          spatialFeatureId: 'SPF-LP-000123',
        );

        final replacement = Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.702),
          Wgs84Vertex(latitude: 16.501, longitude: 104.702),
          Wgs84Vertex(latitude: 16.501, longitude: 104.7),
        ]);

        final updated = original.replaceBoundary(
          boundary: replacement,
          source: BoundarySource.googleEarth,
          verificationStatus: BoundaryVerificationStatus.draft,
          actorMembershipId: 'member-2',
          occurredAt: capturedAt.add(const Duration(hours: 1)),
        );

        expect(updated.spatialFeatureId, original.spatialFeatureId);
        expect(updated.spatialFeatureId, 'SPF-LP-000123');
      },
    );

    test('11. existing geometry contract still works', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
      );

      expect(parcel.boundary, isNotNull);
      expect(parcel.centroid, isNotNull);
      expect(parcel.areaM2, greaterThan(0));
      expect(parcel.perimeterM, greaterThan(0));
    });

    test('12. existing boundary history still works', () {
      final parcel = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
      );

      expect(parcel.boundaryVersion, 1);
      expect(parcel.boundaryHistory, hasLength(1));
    });
  });

  // ============================================================
  // CropRecord
  // ============================================================
  group('CropRecord', () {
    test('13. valid CropRecord links to parcelId', () {
      final crop = CropRecord(
        id: 'crop-1',
        parcelId: 'parcel-1',
        cropType: 'cassava',
        quantity: 1200,
        unit: 'tree',
        condition: CropCondition.growing,
        active: true,
        createdAt: capturedAt,
        createdBy: 'user-1',
        updatedAt: capturedAt,
        updatedBy: 'user-1',
      );

      expect(crop.parcelId, 'parcel-1');
    });

    test('14. multiple CropRecords can reference same parcelId', () {
      final crop1 = CropRecord(
        id: 'crop-1',
        parcelId: 'parcel-1',
        cropType: 'cassava',
        quantity: 1200,
        unit: 'tree',
        condition: CropCondition.growing,
        active: true,
        createdAt: capturedAt,
        createdBy: 'user-1',
        updatedAt: capturedAt,
        updatedBy: 'user-1',
      );

      final crop2 = CropRecord(
        id: 'crop-2',
        parcelId: 'parcel-1',
        cropType: 'rubber',
        quantity: 350,
        unit: 'tree',
        condition: CropCondition.growing,
        active: true,
        createdAt: capturedAt,
        createdBy: 'user-1',
        updatedAt: capturedAt,
        updatedBy: 'user-1',
      );

      expect(crop1.parcelId, crop2.parcelId);
      expect(crop1.id, isNot(crop2.id));
    });

    test('15. cropType + quantity remain supported', () {
      final crop = CropRecord(
        id: 'crop-1',
        parcelId: 'parcel-1',
        cropType: 'rice',
        quantity: 500.5,
        unit: 'kg',
        condition: CropCondition.harvested,
        active: false,
        createdAt: capturedAt,
        createdBy: 'user-1',
        updatedAt: capturedAt,
        updatedBy: 'user-1',
      );

      expect(crop.cropType, 'rice');
      expect(crop.quantity, 500.5);
    });

    test('16. Vietnamese/Lao crop text remains supported', () {
      final vnCrop = CropRecord(
        id: 'crop-vn',
        parcelId: 'parcel-1',
        cropType: 'Lúa nước',
        quantity: 300,
        unit: 'kg',
        condition: CropCondition.growing,
        active: true,
        createdAt: capturedAt,
        createdBy: 'user-1',
        updatedAt: capturedAt,
        updatedBy: 'user-1',
      );

      expect(vnCrop.cropType, 'Lúa nước');

      final laoCrop = CropRecord(
        id: 'crop-lao',
        parcelId: 'parcel-1',
        cropType: 'ມັນຕົ້ນ',
        quantity: 500,
        unit: 'tree',
        condition: CropCondition.growing,
        active: true,
        createdAt: capturedAt,
        createdBy: 'user-1',
        updatedAt: capturedAt,
        updatedBy: 'user-1',
      );

      expect(laoCrop.cropType, 'ມັນຕົ້ນ');
    });
  });

  // ============================================================
  // LandParcelMapper round-trip for 6 new fields
  // ============================================================
  group('LandParcelMapper round-trip', () {
    test('17. all 6 new fields survive JSON round-trip', () {
      final original = LandParcel.create(
        id: 'parcel-1',
        farmId: 'farm-1',
        parcelCode: 'P-001',
        name: 'Field A',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
        spatialFeatureId: 'SPF-LP-000123',
        countryCode: 'LA',
        provinceCode: 'SVK',
        districtCode: 'NONG',
        villageCode: 'TAKO',
        ownerContact: '+856 20 12345678',
      );

      final json = LandParcelMapper.toJson(original);
      final restored = LandParcelMapper.fromJson(json);

      expect(restored.spatialFeatureId, original.spatialFeatureId);
      expect(restored.spatialFeatureId, 'SPF-LP-000123');

      expect(restored.countryCode, original.countryCode);
      expect(restored.countryCode, 'LA');

      expect(restored.provinceCode, original.provinceCode);
      expect(restored.provinceCode, 'SVK');

      expect(restored.districtCode, original.districtCode);
      expect(restored.districtCode, 'NONG');

      expect(restored.villageCode, original.villageCode);
      expect(restored.villageCode, 'TAKO');

      expect(restored.ownerContact, original.ownerContact);
      expect(restored.ownerContact, '+856 20 12345678');
    });

    test('18. null new fields survive JSON round-trip', () {
      final original = LandParcel.create(
        id: 'parcel-2',
        farmId: 'farm-1',
        parcelCode: 'P-002',
        name: 'Field B',
        boundary: boundary,
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: capturedAt,
      );

      final json = LandParcelMapper.toJson(original);
      final restored = LandParcelMapper.fromJson(json);

      expect(restored.spatialFeatureId, isNull);
      expect(restored.countryCode, isNull);
      expect(restored.provinceCode, isNull);
      expect(restored.districtCode, isNull);
      expect(restored.villageCode, isNull);
      expect(restored.ownerContact, isNull);
    });
  });
}