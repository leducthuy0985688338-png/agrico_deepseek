import '../entities/land_survey.dart';

abstract interface class LandSurveyRepository {
  Future<void> createHousehold(Household value);
  Future<void> updateHousehold(Household value);
  Future<Household?> getHousehold(String id);
  Future<List<Household>> listHouseholds(String farmId);
  Future<void> createSurvey(LandParcelSurvey value);
  Future<List<LandParcelSurvey>> listSurveys(String parcelId);
  Future<void> saveLandUseProfile(LandUseProfile value);
  Future<LandUseProfile?> getLandUseProfile(String parcelId);
  Future<void> createCrop(CropRecord value);
  Future<void> updateCrop(CropRecord value);
  Future<List<CropRecord>> listCrops(
    String parcelId, {
    bool includeInactive = false,
  });
  Future<void> createAttachment(ParcelAttachment value);
  Future<List<ParcelAttachment>> listAttachments(String parcelId);
  Future<T> transaction<T>(
    Future<T> Function(LandSurveyRepository repository) action,
  );
}
