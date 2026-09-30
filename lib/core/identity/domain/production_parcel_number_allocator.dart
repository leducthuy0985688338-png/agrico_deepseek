import 'production_parcel_reference_code.dart';

/// Allocation and record persistence must share the caller's transaction.
abstract interface class ProductionParcelNumberAllocator {
  Future<T> saveLandBlock<T>({
    required String farmId,
    required String projectCode,
    required Future<T> Function(ProductionParcelReferenceCode code) save,
  });

  Future<T> saveFieldPlot<T>({
    required String farmId,
    required ProductionParcelReferenceCode parent,
    required Future<T> Function(ProductionParcelReferenceCode code) save,
  });
}
