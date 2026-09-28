/// New land-only parcel code, independent of household records.
/// Previously issued household-based codes remain unchanged.
class LocationParcelReferenceCode {
  LocationParcelReferenceCode({
    required this.countryCode,
    required this.provinceCode,
    required this.districtCode,
    required this.villageCode,
    required this.number,
  }) {
    for (final segment in [countryCode, provinceCode, districtCode, villageCode]) {
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(segment)) {
        throw const FormatException('Invalid catalogued administrative code.');
      }
    }
    if (number < 1 || number > 99999) {
      throw const FormatException('Parcel number must be 00001–99999.');
    }
  }

  final String countryCode;
  final String provinceCode;
  final String districtCode;
  final String villageCode;
  final int number;

  @override
  String toString() => '$countryCode-$provinceCode-$districtCode-'
      '$villageCode-L${number.toString().padLeft(5, '0')}';
}
