import 'land_parcel.dart';

enum LandUseType { agricultural, residential, forest, pasture, mixed, other }

enum LandCondition { unknown, unused, cultivated, degraded, flooded, other }

enum ClearingStatus { unknown, notRequired, notStarted, partial, completed }

enum ReadinessStatus { unknown, notReady, preparation, ready }

enum CropCondition { unknown, planned, growing, healthy, stressed, harvested }

enum ParcelAttachmentType { photo, document, other }

class AdministrativeLocation {
  const AdministrativeLocation({
    required this.countryName,
    required this.provinceName,
    required this.districtName,
    required this.villageName,
    this.countryCode,
    this.provinceCode,
    this.districtCode,
    this.villageCode,
  });

  final String? countryCode;
  final String countryName;
  final String? provinceCode;
  final String provinceName;
  final String? districtCode;
  final String districtName;
  final String? villageCode;
  final String villageName;
}

class Household {
  const Household({
    required this.id,
    required this.farmId,
    required this.householdCode,
    required this.headOfHouseholdName,
    required this.administrativeLocation,
    required this.active,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.phone,
    this.alternativeContact,
    this.address,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;
  final String id;
  final String farmId;
  final String householdCode;
  final String headOfHouseholdName;
  final String? phone;
  final String? alternativeContact;
  final AdministrativeLocation administrativeLocation;
  final String? address;
  final String? notes;
  final bool active;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  final int schemaVersion;
  void validate() {
    _requireText(id, 'id');
    _requireText(farmId, 'farmId');
    _requireText(householdCode, 'householdCode');
    _requireText(headOfHouseholdName, 'headOfHouseholdName');
    _requireText(createdBy, 'createdBy');
    _requireText(updatedBy, 'updatedBy');

    _validateOptionalText(phone, 'phone');
    _validateOptionalText(alternativeContact, 'alternativeContact');
    _validateOptionalText(address, 'address');
    _validateOptionalText(notes, 'notes');

    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException(
        'Household updatedAt cannot be before createdAt.',
      );
    }

    if (schemaVersion <= 0) {
      throw const FormatException(
        'Household schemaVersion must be greater than zero.',
      );
    }
  }

  static void _requireText(String value, String fieldName) {
    if (value.trim().isEmpty) {
      throw FormatException('Household $fieldName cannot be blank.');
    }
  }

  static void _validateOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Household $fieldName cannot be blank when provided.',
      );
    }
  }
}

class LandParcelSurvey {
  const LandParcelSurvey({
    required this.id,
    required this.parcelId,
    required this.surveyDate,
    required this.surveyorMembershipId,
    required this.boundarySource,
    required this.verificationStatus,
    required this.boundaryVersion,
    required this.createdAt,
    required this.createdBy,
    this.boundaryConfidence,
    this.horizontalAccuracyM,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;
  final String id;
  final String parcelId;
  final DateTime surveyDate;
  final String surveyorMembershipId;
  final BoundarySource boundarySource;
  final BoundaryVerificationStatus verificationStatus;
  final double? boundaryConfidence;
  final double? horizontalAccuracyM;
  final int boundaryVersion;
  final String? notes;
  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;
}

class LandUseProfile {
  const LandUseProfile({
    required this.parcelId,
    required this.landUseType,
    required this.currentCondition,
    required this.clearingStatus,
    required this.readinessStatus,
    required this.updatedAt,
    required this.updatedBy,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;
  final String parcelId;
  final LandUseType landUseType;
  final LandCondition currentCondition;
  final ClearingStatus clearingStatus;
  final ReadinessStatus readinessStatus;
  final String? notes;
  final DateTime updatedAt;
  final String updatedBy;
  final int schemaVersion;

  /// Domain validation for LandUseProfile.
  ///
  /// Sprint 11: business metadata invariant. Enforced at domain boundary.
  /// Application layer must NOT duplicate this validation.
  void validate() {
    if (parcelId.trim().isEmpty) {
      throw const FormatException(
        'LandUseProfile parcelId cannot be blank.',
      );
    }
    if (updatedBy.trim().isEmpty) {
      throw const FormatException(
        'LandUseProfile updatedBy cannot be blank.',
      );
    }
    if (notes != null && notes!.trim().isEmpty) {
      throw const FormatException(
        'LandUseProfile notes cannot be blank when provided.',
      );
    }
    if (schemaVersion <= 0) {
      throw const FormatException(
        'LandUseProfile schemaVersion must be greater than zero.',
      );
    }
  }
}

class CropRecord {
  const CropRecord({
    required this.id,
    required this.parcelId,
    required this.cropType,
    required this.quantity,
    required this.unit,
    required this.condition,
    required this.active,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.variety,
    this.plantingYear,
    this.plantingDate,
    this.ageMonths,
    this.notes,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;
  final String id;
  final String parcelId;
  final String cropType;
  final double quantity;
  final String unit;
  final String? variety;
  final int? plantingYear;
  final DateTime? plantingDate;
  /// Age recorded for this crop, in complete months; null when unknown.
  final int? ageMonths;
  final CropCondition condition;
  final String? notes;
  final bool active;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  final int schemaVersion;
}

class ParcelAttachment {
  const ParcelAttachment({
    required this.id,
    required this.parcelId,
    required this.attachmentType,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
    required this.createdBy,
    this.localReference,
    this.cloudReference,
    this.description,
    this.capturedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;
  final String id;
  final String parcelId;
  final ParcelAttachmentType attachmentType;
  final String fileName;
  final String mimeType;
  final String? localReference;
  final String? cloudReference;
  final String? description;
  final DateTime? capturedAt;
  final DateTime createdAt;
  final String createdBy;
  final int schemaVersion;
}
