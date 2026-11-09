import '../../../../models/field_model.dart';
import '../../domain/repositories/land_parcel_repository.dart';
import 'legacy_field_adapter.dart';

enum LegacyMigrationSkipReason {
  malformedRecord,
  invalidGeometry,
  existingParcel,
  duplicateParcelCode,
}

class LegacyMigrationSkippedRecord {
  const LegacyMigrationSkippedRecord({
    required this.legacyId,
    required this.reason,
    required this.message,
  });

  final String? legacyId;
  final LegacyMigrationSkipReason reason;
  final String message;
}

class LandParcelLegacyMigrationReport {
  LandParcelLegacyMigrationReport({
    required List<String> migratedIds,
    required List<LegacyMigrationSkippedRecord> skipped,
  }) : migratedIds = List.unmodifiable(migratedIds),
       skipped = List.unmodifiable(skipped);

  final List<String> migratedIds;
  final List<LegacyMigrationSkippedRecord> skipped;
}

class LandParcelLegacyMigration {
  const LandParcelLegacyMigration();

  Future<LandParcelLegacyMigrationReport> migrate({
    required Iterable<Object> legacyRecords,
    required LegacyFieldMigrationPolicy policy,
    required LandParcelRepository repository,
  }) async {
    final migrated = <String>[];
    final skipped = <LegacyMigrationSkippedRecord>[];

    for (final record in legacyRecords) {
      FieldModel field;
      try {
        field = record is FieldModel
            ? record
            : FieldModel.fromJson(Map<String, dynamic>.from(record as Map));
      } catch (error) {
        skipped.add(
          LegacyMigrationSkippedRecord(
            legacyId: record is Map ? record['id']?.toString() : null,
            reason: LegacyMigrationSkipReason.malformedRecord,
            message: '$error',
          ),
        );
        continue;
      }

      if (await repository.getById(farmId: policy.farmId, id: field.id) !=
          null) {
        skipped.add(
          LegacyMigrationSkippedRecord(
            legacyId: field.id,
            reason: LegacyMigrationSkipReason.existingParcel,
            message: 'The legacy field has already been migrated.',
          ),
        );
        continue;
      }

      final parcelCode = policy.parcelCode(field);
      if (await repository.getByParcelCode(
            farmId: policy.farmId,
            parcelCode: parcelCode,
          ) !=
          null) {
        skipped.add(
          LegacyMigrationSkippedRecord(
            legacyId: field.id,
            reason: LegacyMigrationSkipReason.duplicateParcelCode,
            message: 'Parcel code $parcelCode already exists in this farm.',
          ),
        );
        continue;
      }

      try {
        final parcel = LegacyFieldAdapter.toLandParcel(field, policy);
        await repository.create(parcel);
        migrated.add(field.id);
      } on FormatException catch (error) {
        skipped.add(
          LegacyMigrationSkippedRecord(
            legacyId: field.id,
            reason: LegacyMigrationSkipReason.invalidGeometry,
            message: '$error',
          ),
        );
      }
    }

    return LandParcelLegacyMigrationReport(
      migratedIds: migrated,
      skipped: skipped,
    );
  }
}
