/// Production codes are independent of villages, households and crop seasons.
/// This is a display code; it does not replace business or spatial identity.
class ProductionParcelReferenceCode {
  ProductionParcelReferenceCode.landBlock({
    required this.projectCode,
    required this.landBlockNumber,
  }) : fieldPlotNumber = null {
    _validate();
  }

  ProductionParcelReferenceCode.standaloneFieldPlot({
    required this.projectCode,
    required int number,
  }) : landBlockNumber = null,
       fieldPlotNumber = number {
    _validate();
  }

  ProductionParcelReferenceCode.fieldPlot({
    required ProductionParcelReferenceCode parent,
    required int number,
  }) : projectCode = parent.projectCode,
       landBlockNumber = null,
       fieldPlotNumber = number {
    if (parent.landBlockNumber == null || parent.fieldPlotNumber != null) {
      throw const FormatException('A field plot must belong to a land block.');
    }
    _validate();
  }

  final String projectCode;
  final int? landBlockNumber;
  final int? fieldPlotNumber;

  void _validate() {
    if (!RegExp(
          r'^[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*$',
        ).hasMatch(projectCode) ||
        projectCode
            .split('-')
            .any((part) => RegExp(r'^[LT][0-9]+$').hasMatch(part))) {
      throw const FormatException('Invalid production project code.');
    }
    if ((landBlockNumber != null && landBlockNumber! < 1) ||
        (fieldPlotNumber != null && fieldPlotNumber! < 1) ||
        (landBlockNumber == null && fieldPlotNumber == null)) {
      throw const FormatException(
        'Production parcel numbers must be positive.',
      );
    }
  }

  @override
  String toString() {
    if (landBlockNumber == null) {
      return '$projectCode-T${fieldPlotNumber!.toString().padLeft(3, '0')}';
    }
    final block =
        '$projectCode-L${landBlockNumber!.toString().padLeft(3, '0')}';
    return fieldPlotNumber == null
        ? block
        : '$block-T${fieldPlotNumber!.toString().padLeft(3, '0')}';
  }
}
