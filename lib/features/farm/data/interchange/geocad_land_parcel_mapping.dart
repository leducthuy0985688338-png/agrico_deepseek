import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';

abstract final class GeoCadLandParcelMapping {
  static const parcelCode = 'MA_KHOANH';
  static const householdCode = 'MA_HO';
  static const ownerName = 'TEN_CHU_HO';
  static const villageName = 'BAN';
  static const districtName = 'HUYEN';
  static const provinceName = 'TINH';
  static const countryName = 'QUOC_GIA';

  static Map<String, String> exportAttributes(
    LandParcel parcel, {
    Household? household,
  }) => {
    parcelCode: parcel.parcelCode,
    if (household != null) householdCode: household.householdCode,
    if (household != null) ownerName: household.headOfHouseholdName,
    if (household != null)
      villageName: household.administrativeLocation.villageName,
    if (household != null)
      districtName: household.administrativeLocation.districtName,
    if (household != null)
      provinceName: household.administrativeLocation.provinceName,
    if (household != null)
      countryName: household.administrativeLocation.countryName,
  };
}
