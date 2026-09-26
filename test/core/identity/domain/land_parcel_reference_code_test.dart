import 'package:agrico_deepseek/core/identity/domain/land_parcel_reference_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats five-digit household and three-digit parcel numbers', () {
    final code = LandParcelReferenceCode(
      countryCode: 'LA',
      provinceCode: 'SVK',
      districtCode: 'NONG',
      villageCode: 'TAKO',
      householdNumber: 1,
      parcelNumber: 1,
    );
    expect(code.toString(), 'LA-SVK-NONG-TAKO-H00001-001');
  });

  test('same household number in different villages has a different code', () {
    String codeFor(String village) => LandParcelReferenceCode(
      countryCode: 'LA',
      provinceCode: 'SVK',
      districtCode: 'NONG',
      villageCode: village,
      householdNumber: 1,
      parcelNumber: 1,
    ).toString();
    expect(codeFor('TAKO'), isNot(codeFor('OTHERVILLAGE')));
  });

  test('does not wrap exhausted household and parcel ranges', () {
    for (final numbers in [(100000, 1), (1, 1000), (0, 1), (1, 0)]) {
      expect(
        () => LandParcelReferenceCode(
          countryCode: 'LA',
          provinceCode: 'SVK',
          districtCode: 'NONG',
          villageCode: 'TAKO',
          householdNumber: numbers.$1,
          parcelNumber: numbers.$2,
        ),
        throwsFormatException,
      );
    }
  });
}
