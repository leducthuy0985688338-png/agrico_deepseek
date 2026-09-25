/// Transaction-scoped allocation port used by parcel creation.
abstract interface class ParcelNumberAllocator {
  Future<T> saveHousehold<T>({
    required String farmId,
    required Future<T> Function(String householdCode) save,
  });

  Future<T> saveParcel<T>({
    required String farmId,
    required String villageId,
    required int householdNumber,
    required String countryCode,
    required String provinceCode,
    required String districtCode,
    required String villageCode,
    required Future<T> Function(String parcelCode) save,
  });
}
