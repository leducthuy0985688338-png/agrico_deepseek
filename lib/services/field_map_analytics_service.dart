import '../models/field_model.dart';

class FieldMapAnalytics {
  final int totalFields;
  final int mappedFields;
  final double totalAreaSquareMeters;
  final Map<String, double> areaByCrop;
  final Map<String, int> countByStatus;
  final Map<String, int> countByMeasurementMethod;

  const FieldMapAnalytics({
    required this.totalFields,
    required this.mappedFields,
    required this.totalAreaSquareMeters,
    required this.areaByCrop,
    required this.countByStatus,
    required this.countByMeasurementMethod,
  });

  double get totalAreaHa => totalAreaSquareMeters / 10000;

  static FieldMapAnalytics calculate(List<FieldModel> fields) {
    final areaByCrop = <String, double>{};
    final countByStatus = <String, int>{};
    final countByMeasurementMethod = <String, int>{};
    var mapped = 0;
    var totalArea = 0.0;

    for (final field in fields) {
      totalArea += field.area;
      if (field.polygon.length >= 3) mapped++;

      final crop = field.crop.trim().isEmpty ? 'Chưa xác định' : field.crop.trim();
      areaByCrop[crop] = (areaByCrop[crop] ?? 0) + field.area;

      final status = field.status.trim().isEmpty ? 'Chưa xác định' : field.status.trim();
      countByStatus[status] = (countByStatus[status] ?? 0) + 1;

      final method = field.measurementMethod.trim().isEmpty
          ? 'unknown'
          : field.measurementMethod.trim();
      countByMeasurementMethod[method] =
          (countByMeasurementMethod[method] ?? 0) + 1;
    }

    return FieldMapAnalytics(
      totalFields: fields.length,
      mappedFields: mapped,
      totalAreaSquareMeters: totalArea,
      areaByCrop: Map.unmodifiable(areaByCrop),
      countByStatus: Map.unmodifiable(countByStatus),
      countByMeasurementMethod: Map.unmodifiable(countByMeasurementMethod),
    );
  }
}
