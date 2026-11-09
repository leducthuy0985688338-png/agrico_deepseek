import '../../domain/entities/land_survey.dart';
import '../../domain/repositories/land_survey_repository.dart';

class LandSurveyLegacyBundle {
  const LandSurveyLegacyBundle({
    this.household,
    this.landUseProfile,
    this.surveys = const [],
    this.crops = const [],
    this.attachments = const [],
  });

  final Household? household;
  final LandUseProfile? landUseProfile;
  final List<LandParcelSurvey> surveys;
  final List<CropRecord> crops;
  final List<ParcelAttachment> attachments;
}

class LandSurveyMigrationIssue {
  const LandSurveyMigrationIssue(this.recordId, this.reason);
  final String? recordId;
  final String reason;
}

class LandSurveyMigrationReport {
  const LandSurveyMigrationReport({
    required this.insertedIds,
    required this.issues,
  });
  final List<String> insertedIds;
  final List<LandSurveyMigrationIssue> issues;
}

/// Additive and idempotent migration for legacy values that have already been
/// mapped with certainty. Ambiguous source fields must stay in LandParcel's
/// legacyMetadata and must not be passed to this migration.
class LandSurveyLegacyMigration {
  const LandSurveyLegacyMigration(this.repository);
  final LandSurveyRepository repository;

  Future<LandSurveyMigrationReport> migrate(
    Iterable<LandSurveyLegacyBundle> bundles,
  ) async {
    final inserted = <String>[];
    final issues = <LandSurveyMigrationIssue>[];
    for (final bundle in bundles) {
      final recordId =
          bundle.household?.id ??
          bundle.landUseProfile?.parcelId ??
          bundle.crops.firstOrNull?.parcelId ??
          bundle.surveys.firstOrNull?.parcelId ??
          bundle.attachments.firstOrNull?.parcelId;
      try {
        final bundleInserted = <String>[];
        await repository.transaction((txn) async {
          final household = bundle.household;
          if (household != null &&
              await txn.getHousehold(household.id) == null) {
            await txn.createHousehold(household);
            bundleInserted.add(household.id);
          }
          final profile = bundle.landUseProfile;
          if (profile != null &&
              await txn.getLandUseProfile(profile.parcelId) == null) {
            await txn.saveLandUseProfile(profile);
            bundleInserted.add('landUse:${profile.parcelId}');
          }
          for (final survey in bundle.surveys) {
            final ids = (await txn.listSurveys(
              survey.parcelId,
            )).map((value) => value.id);
            if (!ids.contains(survey.id)) {
              await txn.createSurvey(survey);
              bundleInserted.add(survey.id);
            }
          }
          for (final crop in bundle.crops) {
            final ids = (await txn.listCrops(
              crop.parcelId,
              includeInactive: true,
            )).map((value) => value.id);
            if (!ids.contains(crop.id)) {
              await txn.createCrop(crop);
              bundleInserted.add(crop.id);
            }
          }
          for (final attachment in bundle.attachments) {
            final ids = (await txn.listAttachments(
              attachment.parcelId,
            )).map((value) => value.id);
            if (!ids.contains(attachment.id)) {
              await txn.createAttachment(attachment);
              bundleInserted.add(attachment.id);
            }
          }
        });
        inserted.addAll(bundleInserted);
      } catch (error) {
        issues.add(LandSurveyMigrationIssue(recordId, error.toString()));
      }
    }
    return LandSurveyMigrationReport(
      insertedIds: List.unmodifiable(inserted),
      issues: List.unmodifiable(issues),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
