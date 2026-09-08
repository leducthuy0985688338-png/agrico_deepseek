import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';

abstract final class LandSurveyMapper {
  static Map<String, Object?> locationToJson(AdministrativeLocation value) => {
    'countryCode': value.countryCode,
    'countryName': value.countryName,
    'provinceCode': value.provinceCode,
    'provinceName': value.provinceName,
    'districtCode': value.districtCode,
    'districtName': value.districtName,
    'villageCode': value.villageCode,
    'villageName': value.villageName,
  };

  static AdministrativeLocation locationFromJson(Map<String, Object?> json) =>
      AdministrativeLocation(
        countryCode: json['countryCode'] as String?,
        countryName: json['countryName']! as String,
        provinceCode: json['provinceCode'] as String?,
        provinceName: json['provinceName']! as String,
        districtCode: json['districtCode'] as String?,
        districtName: json['districtName']! as String,
        villageCode: json['villageCode'] as String?,
        villageName: json['villageName']! as String,
      );

  static Map<String, Object?> householdToJson(Household value) => {
    'id': value.id,
    'farmId': value.farmId,
    'householdCode': value.householdCode,
    'headOfHouseholdName': value.headOfHouseholdName,
    'phone': value.phone,
    'alternativeContact': value.alternativeContact,
    'administrativeLocation': locationToJson(value.administrativeLocation),
    'address': value.address,
    'notes': value.notes,
    'active': value.active,
    'createdAt': _date(value.createdAt),
    'createdBy': value.createdBy,
    'updatedAt': _date(value.updatedAt),
    'updatedBy': value.updatedBy,
    'schemaVersion': value.schemaVersion,
  };

  static Household householdFromJson(Map<String, Object?> json) => Household(
    id: json['id']! as String,
    farmId: json['farmId']! as String,
    householdCode: json['householdCode']! as String,
    headOfHouseholdName: json['headOfHouseholdName']! as String,
    phone: json['phone'] as String?,
    alternativeContact: json['alternativeContact'] as String?,
    administrativeLocation: locationFromJson(
      _map(json['administrativeLocation']),
    ),
    address: json['address'] as String?,
    notes: json['notes'] as String?,
    active: json['active']! as bool,
    createdAt: _parse(json['createdAt']),
    createdBy: json['createdBy']! as String,
    updatedAt: _parse(json['updatedAt']),
    updatedBy: json['updatedBy']! as String,
    schemaVersion: json['schemaVersion']! as int,
  );

  static Map<String, Object?> surveyToJson(LandParcelSurvey value) => {
    'id': value.id,
    'parcelId': value.parcelId,
    'surveyDate': _date(value.surveyDate),
    'surveyorMembershipId': value.surveyorMembershipId,
    'boundarySource': value.boundarySource.name,
    'verificationStatus': value.verificationStatus.name,
    'boundaryConfidence': value.boundaryConfidence,
    'horizontalAccuracyM': value.horizontalAccuracyM,
    'boundaryVersion': value.boundaryVersion,
    'notes': value.notes,
    'createdAt': _date(value.createdAt),
    'createdBy': value.createdBy,
    'schemaVersion': value.schemaVersion,
  };

  static LandParcelSurvey surveyFromJson(Map<String, Object?> json) =>
      LandParcelSurvey(
        id: json['id']! as String,
        parcelId: json['parcelId']! as String,
        surveyDate: _parse(json['surveyDate']),
        surveyorMembershipId: json['surveyorMembershipId']! as String,
        boundarySource: BoundarySource.values.byName(
          json['boundarySource']! as String,
        ),
        verificationStatus: BoundaryVerificationStatus.values.byName(
          json['verificationStatus']! as String,
        ),
        boundaryConfidence: (json['boundaryConfidence'] as num?)?.toDouble(),
        horizontalAccuracyM: (json['horizontalAccuracyM'] as num?)?.toDouble(),
        boundaryVersion: json['boundaryVersion']! as int,
        notes: json['notes'] as String?,
        createdAt: _parse(json['createdAt']),
        createdBy: json['createdBy']! as String,
        schemaVersion: json['schemaVersion']! as int,
      );

  static Map<String, Object?> landUseToJson(LandUseProfile value) => {
    'parcelId': value.parcelId,
    'landUseType': value.landUseType.name,
    'currentCondition': value.currentCondition.name,
    'clearingStatus': value.clearingStatus.name,
    'readinessStatus': value.readinessStatus.name,
    'notes': value.notes,
    'updatedAt': _date(value.updatedAt),
    'updatedBy': value.updatedBy,
    'schemaVersion': value.schemaVersion,
  };

  static LandUseProfile landUseFromJson(Map<String, Object?> json) =>
      LandUseProfile(
        parcelId: json['parcelId']! as String,
        landUseType: LandUseType.values.byName(json['landUseType']! as String),
        currentCondition: LandCondition.values.byName(
          json['currentCondition']! as String,
        ),
        clearingStatus: ClearingStatus.values.byName(
          json['clearingStatus']! as String,
        ),
        readinessStatus: ReadinessStatus.values.byName(
          json['readinessStatus']! as String,
        ),
        notes: json['notes'] as String?,
        updatedAt: _parse(json['updatedAt']),
        updatedBy: json['updatedBy']! as String,
        schemaVersion: json['schemaVersion']! as int,
      );

  static Map<String, Object?> cropToJson(CropRecord value) => {
    'id': value.id,
    'parcelId': value.parcelId,
    'cropType': value.cropType,
    'quantity': value.quantity,
    'unit': value.unit,
    'variety': value.variety,
    'plantingYear': value.plantingYear,
    'plantingDate': value.plantingDate == null
        ? null
        : _date(value.plantingDate!),
    'condition': value.condition.name,
    'notes': value.notes,
    'active': value.active,
    'createdAt': _date(value.createdAt),
    'createdBy': value.createdBy,
    'updatedAt': _date(value.updatedAt),
    'updatedBy': value.updatedBy,
    'schemaVersion': value.schemaVersion,
  };

  static CropRecord cropFromJson(Map<String, Object?> json) => CropRecord(
    id: json['id']! as String,
    parcelId: json['parcelId']! as String,
    cropType: json['cropType']! as String,
    quantity: (json['quantity']! as num).toDouble(),
    unit: json['unit']! as String,
    variety: json['variety'] as String?,
    plantingYear: json['plantingYear'] as int?,
    plantingDate: json['plantingDate'] == null
        ? null
        : _parse(json['plantingDate']),
    condition: CropCondition.values.byName(json['condition']! as String),
    notes: json['notes'] as String?,
    active: json['active']! as bool,
    createdAt: _parse(json['createdAt']),
    createdBy: json['createdBy']! as String,
    updatedAt: _parse(json['updatedAt']),
    updatedBy: json['updatedBy']! as String,
    schemaVersion: json['schemaVersion']! as int,
  );

  static Map<String, Object?> attachmentToJson(ParcelAttachment value) => {
    'id': value.id,
    'parcelId': value.parcelId,
    'attachmentType': value.attachmentType.name,
    'fileName': value.fileName,
    'mimeType': value.mimeType,
    'localReference': value.localReference,
    'cloudReference': value.cloudReference,
    'description': value.description,
    'capturedAt': value.capturedAt == null ? null : _date(value.capturedAt!),
    'createdAt': _date(value.createdAt),
    'createdBy': value.createdBy,
    'schemaVersion': value.schemaVersion,
  };

  static ParcelAttachment attachmentFromJson(Map<String, Object?> json) =>
      ParcelAttachment(
        id: json['id']! as String,
        parcelId: json['parcelId']! as String,
        attachmentType: ParcelAttachmentType.values.byName(
          json['attachmentType']! as String,
        ),
        fileName: json['fileName']! as String,
        mimeType: json['mimeType']! as String,
        localReference: json['localReference'] as String?,
        cloudReference: json['cloudReference'] as String?,
        description: json['description'] as String?,
        capturedAt: json['capturedAt'] == null
            ? null
            : _parse(json['capturedAt']),
        createdAt: _parse(json['createdAt']),
        createdBy: json['createdBy']! as String,
        schemaVersion: json['schemaVersion']! as int,
      );

  static String _date(DateTime value) => value.toUtc().toIso8601String();
  static DateTime _parse(Object? value) =>
      DateTime.parse(value! as String).toUtc();
  static Map<String, Object?> _map(Object? value) =>
      (value! as Map).map((key, value) => MapEntry(key.toString(), value));
}
