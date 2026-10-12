enum ProductionCostParcelMode { all, general, parcel }

class ProductionCostParcelFilter {
  const ProductionCostParcelFilter.all()
    : mode = ProductionCostParcelMode.all,
      parcelId = null;
  const ProductionCostParcelFilter.general()
    : mode = ProductionCostParcelMode.general,
      parcelId = null;
  const ProductionCostParcelFilter.parcel(this.parcelId)
    : mode = ProductionCostParcelMode.parcel;
  final ProductionCostParcelMode mode;
  final String? parcelId;

  void validate() {
    if (mode == ProductionCostParcelMode.parcel &&
        (parcelId == null || parcelId!.trim().isEmpty)) {
      throw const FormatException('Parcel filter requires an ID.');
    }
  }

  bool contains(String? id) => switch (mode) {
    ProductionCostParcelMode.all => true,
    ProductionCostParcelMode.general => id == null,
    ProductionCostParcelMode.parcel => id == parcelId,
  };
}
