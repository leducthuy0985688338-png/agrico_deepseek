import 'package:sqflite/sqflite.dart';

import '../domain/parcel_number_allocator.dart';
import 'sqlite_parcel_number_sequence.dart';

class SqliteScopedParcelNumberAllocator implements ParcelNumberAllocator {
  const SqliteScopedParcelNumberAllocator(this.transaction);

  final Transaction transaction;

  @override
  Future<T> saveHousehold<T>({
    required String farmId,
    required Future<T> Function(String householdCode) save,
  }) => SqliteParcelNumberSequence().saveHousehold(
    tx: transaction, farmId: farmId, save: save,
  );

  @override
  Future<T> saveParcel<T>({
    required String farmId,
    required String villageId,
    required int householdNumber,
    required String countryCode,
    required String provinceCode,
    required String districtCode,
    required String villageCode,
    required Future<T> Function(String parcelCode) save,
  }) => SqliteParcelNumberSequence().saveParcel(
    tx: transaction, farmId: farmId, villageId: villageId,
    householdNumber: householdNumber, countryCode: countryCode,
    provinceCode: provinceCode, districtCode: districtCode,
    villageCode: villageCode, save: save,
  );
}
