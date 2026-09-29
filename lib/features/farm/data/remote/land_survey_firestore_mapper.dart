import '../../domain/entities/land_survey.dart';
import '../models/land_survey_mapper.dart';

abstract final class LandSurveyFirestoreMapper {
  static String householdPath(Household value) => 'households/${value.id}';
  static String surveyPath(LandParcelSurvey value) =>
      'landParcels/${value.parcelId}/surveys/${value.id}';
  static String landUsePath(LandUseProfile value) =>
      'landParcels/${value.parcelId}/landUse/profile';
  static String cropPath(CropRecord value) =>
      'landParcels/${value.parcelId}/crops/${value.id}';
  static String attachmentPath(ParcelAttachment value) =>
      'landParcels/${value.parcelId}/attachments/${value.id}';
  static Map<String, Object?> household(Household value) =>
      LandSurveyMapper.householdToJson(value);
  static Map<String, Object?> survey(LandParcelSurvey value) =>
      LandSurveyMapper.surveyToJson(value);
  static Map<String, Object?> landUse(LandUseProfile value) =>
      LandSurveyMapper.landUseToJson(value);
  static Map<String, Object?> crop(CropRecord value) =>
      LandSurveyMapper.cropToJson(value);
  static Map<String, Object?> attachment(ParcelAttachment value) =>
      LandSurveyMapper.attachmentToJson(value);

  static Household householdFromDocument(Map<String, Object?> value) =>
      LandSurveyMapper.householdFromJson(value);
  static LandParcelSurvey surveyFromDocument(Map<String, Object?> value) =>
      LandSurveyMapper.surveyFromJson(value);
  static LandUseProfile landUseFromDocument(Map<String, Object?> value) =>
      LandSurveyMapper.landUseFromJson(value);
  static CropRecord cropFromDocument(Map<String, Object?> value) =>
      LandSurveyMapper.cropFromJson(value);
  static ParcelAttachment attachmentFromDocument(Map<String, Object?> value) =>
      LandSurveyMapper.attachmentFromJson(value);
}
