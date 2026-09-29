import 'package:agrico_deepseek/features/farm/data/interchange/geocad_land_parcel_mapping.dart';
import 'package:agrico_deepseek/features/farm/data/interchange/kml_interchange.dart';
import 'package:agrico_deepseek/features/farm/data/legacy/land_survey_legacy_migration.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/data/remote/land_survey_firestore_mapper.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late LandSurveyRepository surveys;
  late SqliteLandParcelRepository parcels;
  final timestamp = DateTime.utc(2026, 9, 8, 10, 30);

  AdministrativeLocation location() => const AdministrativeLocation(
    countryCode: 'LA',
    countryName: 'ລາວ',
    provinceName: 'ສະຫວັນນະເຂດ',
    districtName: 'ໄກສອນ',
    villageName: 'ບ້ານ ນາໂພ',
  );

  Household household({String id = 'hh-1', String code = 'H-001'}) => Household(
    id: id,
    farmId: 'farm-1',
    householdCode: code,
    headOfHouseholdName: 'Nguyễn Văn An ສົມພອນ',
    phone: '02055555555',
    administrativeLocation: location(),
    active: true,
    createdAt: timestamp,
    createdBy: 'member-1',
    updatedAt: timestamp,
    updatedBy: 'member-1',
  );

  LandParcel parcel({String id = 'parcel-1', String code = 'P-001'}) =>
      LandParcel.create(
        id: id,
        farmId: 'farm-1',
        parcelCode: code,
        name: 'Khoảnh ດິນ $code',
        ownerHouseholdId: 'hh-1',
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.701),
          Wgs84Vertex(latitude: 16.501, longitude: 104.7),
        ]),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: timestamp,
      );

  CropRecord crop(String id, String type) => CropRecord(
    id: id,
    parcelId: 'parcel-1',
    cropType: type,
    quantity: 125.5,
    unit: 'tree',
    variety: 'ພັນພື້ນເມືອງ',
    plantingYear: 2024,
    condition: CropCondition.healthy,
    active: true,
    createdAt: timestamp,
    createdBy: 'member-1',
    updatedAt: timestamp,
    updatedBy: 'member-1',
  );

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteLandSurveyRepository.createSchema(database);
    await SqliteLandSurveyRepository.createSchema(database);
    surveys = SqliteLandSurveyRepository(database);
    parcels = SqliteLandParcelRepository(database);
    await surveys.createHousehold(household());
    await parcels.create(parcel());
  });

  tearDown(() => database.close());

  test(
    'one household owns many parcels and parcel can have no crops',
    () async {
      await parcels.create(parcel(id: 'parcel-2', code: 'P-002'));
      final owned = (await parcels.listByFarm(
        'farm-1',
      )).where((value) => value.ownerHouseholdId == 'hh-1');

      expect(owned, hasLength(2));
      expect(await surveys.listCrops('parcel-1'), isEmpty);
    },
  );

  test('parcel supports one and then unlimited crop records', () async {
    await surveys.createCrop(crop('crop-1', 'rice'));
    expect(await surveys.listCrops('parcel-1'), hasLength(1));
    await surveys.createCrop(crop('crop-2', 'coffee'));
    await surveys.createCrop(crop('crop-3', 'banana'));
    expect(
      (await surveys.listCrops('parcel-1')).map((value) => value.cropType),
      ['rice', 'coffee', 'banana'],
    );
  });

  test('household and crop persistence round trip preserve Unicode', () async {
    final restoredHousehold = await surveys.getHousehold('hh-1');
    await surveys.createCrop(crop('crop-1', 'Cà phê ກາເຟ'));
    final restoredCrop = (await surveys.listCrops('parcel-1')).single;

    expect(restoredHousehold?.headOfHouseholdName, 'Nguyễn Văn An ສົມພອນ');
    expect(restoredHousehold?.administrativeLocation.villageName, 'ບ້ານ ນາໂພ');
    expect(restoredCrop.cropType, 'Cà phê ກາເຟ');
    expect(restoredCrop.quantity, 125.5);
  });

  test('survey land-use and attachment metadata round trip', () async {
    final survey = LandParcelSurvey(
      id: 'survey-1',
      parcelId: 'parcel-1',
      surveyDate: timestamp,
      surveyorMembershipId: 'member-1',
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      boundaryConfidence: .95,
      horizontalAccuracyM: 1.2,
      boundaryVersion: 1,
      notes: 'Đo tại ບ້ານ',
      createdAt: timestamp,
      createdBy: 'member-1',
    );
    final landUse = LandUseProfile(
      parcelId: 'parcel-1',
      landUseType: LandUseType.agricultural,
      currentCondition: LandCondition.cultivated,
      clearingStatus: ClearingStatus.completed,
      readinessStatus: ReadinessStatus.ready,
      notes: 'Sẵn sàng',
      updatedAt: timestamp,
      updatedBy: 'member-1',
    );
    final attachment = ParcelAttachment(
      id: 'attachment-1',
      parcelId: 'parcel-1',
      attachmentType: ParcelAttachmentType.photo,
      fileName: 'ảnh-ດິນ.jpg',
      mimeType: 'image/jpeg',
      localReference: 'survey/ảnh.jpg',
      cloudReference: 'gs://bucket/photo',
      capturedAt: timestamp,
      createdAt: timestamp,
      createdBy: 'member-1',
    );
    await surveys.createSurvey(survey);
    await surveys.saveLandUseProfile(landUse);
    await surveys.createAttachment(attachment);

    expect((await surveys.listSurveys('parcel-1')).single.notes, 'Đo tại ບ້ານ');
    expect(
      (await surveys.getLandUseProfile('parcel-1'))?.readinessStatus,
      ReadinessStatus.ready,
    );
    expect(
      (await surveys.listAttachments('parcel-1')).single.fileName,
      'ảnh-ດິນ.jpg',
    );
  });

  test('foreign keys reject orphan child records', () async {
    expect(
      () => surveys.createCrop(
        CropRecord(
          id: 'orphan',
          parcelId: 'missing',
          cropType: 'rice',
          quantity: 1,
          unit: 'kg',
          condition: CropCondition.unknown,
          active: true,
          createdAt: timestamp,
          createdBy: 'member-1',
          updatedAt: timestamp,
          updatedBy: 'member-1',
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('duplicate household code and transaction failure roll back', () async {
    expect(
      () => surveys.createHousehold(household(id: 'hh-2')),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      surveys.transaction((txn) async {
        await txn.createCrop(crop('crop-1', 'rice'));
        await txn.createCrop(crop('crop-1', 'duplicate'));
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await surveys.listCrops('parcel-1'), isEmpty);
  });

  test('KML canonical metadata and GeoCAD names round trip', () {
    final sourceParcel = parcel();
    final profile = LandUseProfile(
      parcelId: sourceParcel.id,
      landUseType: LandUseType.agricultural,
      currentCondition: LandCondition.cultivated,
      clearingStatus: ClearingStatus.completed,
      readinessStatus: ReadinessStatus.ready,
      updatedAt: timestamp,
      updatedBy: 'member-1',
    );
    const codec = KmlInterchangeCodec();
    final imported = codec
        .importKml(
          codec.exportKml(
            sourceParcel,
            metadata: LandParcelExchangeMetadata(
              household: household(),
              landUseProfile: profile,
            ),
          ),
        )
        .previews
        .single
        .metadata;
    final cad = GeoCadLandParcelMapping.exportAttributes(
      sourceParcel,
      household: household(),
    );

    expect(imported.householdCode, 'H-001');
    expect(imported.ownerName, 'Nguyễn Văn An ສົມພອນ');
    expect(imported.village, 'ບ້ານ ນາໂພ');
    expect(imported.landUse, 'agricultural');
    expect(cad[GeoCadLandParcelMapping.parcelCode], 'P-001');
    expect(cad[GeoCadLandParcelMapping.householdCode], 'H-001');
    expect(cad[GeoCadLandParcelMapping.ownerName], 'Nguyễn Văn An ສົມພອນ');
    expect(cad[GeoCadLandParcelMapping.villageName], 'ບ້ານ ນາໂພ');
  });

  test('Firestore contract keeps survey records in separate collections', () {
    final value = crop('crop-1', 'rice');
    expect(
      LandSurveyFirestoreMapper.householdPath(household()),
      'households/hh-1',
    );
    expect(
      LandSurveyFirestoreMapper.cropPath(value),
      'landParcels/parcel-1/crops/crop-1',
    );
    expect(LandSurveyFirestoreMapper.crop(value)['cropType'], 'rice');
  });

  test(
    'legacy survey migration is idempotent and skips malformed bundle',
    () async {
      final migration = LandSurveyLegacyMigration(surveys);
      final valid = LandSurveyLegacyBundle(
        crops: [crop('crop-legacy', 'rice')],
      );
      final malformed = LandSurveyLegacyBundle(
        crops: [
          CropRecord(
            id: 'orphan',
            parcelId: 'missing',
            cropType: 'unknown',
            quantity: 1,
            unit: 'kg',
            condition: CropCondition.unknown,
            active: true,
            createdAt: timestamp,
            createdBy: 'member-1',
            updatedAt: timestamp,
            updatedBy: 'member-1',
          ),
        ],
      );

      final first = await migration.migrate([valid, malformed]);
      final second = await migration.migrate([valid]);

      expect(first.insertedIds, ['crop-legacy']);
      expect(first.issues, hasLength(1));
      expect(second.insertedIds, isEmpty);
      expect(await surveys.listCrops('parcel-1'), hasLength(1));
    },
  );
}
