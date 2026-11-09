/// AGRICO display code for a parcel in one village and household.
///
/// The administrative segments must come from the approved catalog. This
/// formatter does not assign administrative identities or allocate numbers.
class LandParcelReferenceCode {
  LandParcelReferenceCode({
    required this.countryCode,
    required this.provinceCode,
    required this.districtCode,
    required this.villageCode,
    required this.householdNumber,
    required this.parcelNumber,
  }) {
    for (final segment in [
      countryCode,
      provinceCode,
      districtCode,
      villageCode,
    ]) {
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(segment)) {
        throw const FormatException('Invalid catalogued administrative code.');
      }
    }
    if (householdNumber < 1 || householdNumber > 99999 ||
        parcelNumber < 1 || parcelNumber > 999) {
      throw const FormatException('Household number must be 00001–99999 and parcel number 001–999.');
    }
  }

  final String countryCode;
  final String provinceCode;
  final String districtCode;
  final String villageCode;
  final int householdNumber;
  final int parcelNumber;

  @override
  String toString() =>
      '$countryCode-$provinceCode-$districtCode-$villageCode-'
      'H${householdNumber.toString().padLeft(5, '0')}-'
      '${parcelNumber.toString().padLeft(3, '0')}';
}
