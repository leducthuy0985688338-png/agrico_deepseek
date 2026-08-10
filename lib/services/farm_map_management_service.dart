import '../models/field_model.dart';

class FarmMapSummary {
  final List<FieldModel> fields;
  final double totalArea;
  final Map<String, double> cropArea;
  final Map<String, double> statusArea;
  final Map<String, int> measurementCount;

  const FarmMapSummary({
    required this.fields,
    required this.totalArea,
    required this.cropArea,
    required this.statusArea,
    required this.measurementCount,
  });

  double get totalAreaHa => totalArea / 10000;
}

class FarmMapManagementService {
  const FarmMapManagementService();

  List<FieldModel> filterFields(
    Iterable<FieldModel> source, {
    String query = '',
    String crop = 'Tất cả',
    String status = 'Tất cả',
    double? minAreaHa,
    double? maxAreaHa,
    bool requirePolygon = true,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    return source.where((field) {
      if (requirePolygon && field.polygon.length < 3) return false;
      final searchOk = normalizedQuery.isEmpty ||
          field.id.toLowerCase().contains(normalizedQuery) ||
          field.name.toLowerCase().contains(normalizedQuery);
      final cropOk = crop == 'Tất cả' || field.crop == crop;
      final statusOk = status == 'Tất cả' || field.status == status;
      final areaHa = field.area / 10000;
      final minOk = minAreaHa == null || areaHa >= minAreaHa;
      final maxOk = maxAreaHa == null || areaHa <= maxAreaHa;
      return searchOk && cropOk && statusOk && minOk && maxOk;
    }).toList(growable: false);
  }

  FarmMapSummary summarize(Iterable<FieldModel> fields) {
    final visible = List<FieldModel>.unmodifiable(fields);
    final cropArea = <String, double>{};
    final statusArea = <String, double>{};
    final measurementCount = <String, int>{};
    var totalArea = 0.0;

    for (final field in visible) {
      totalArea += field.area;
      final crop = field.crop.isEmpty ? 'Chưa xác định' : field.crop;
      final status = field.status.isEmpty ? 'Chưa xác định' : field.status;
      final method = field.measurementMethod.isEmpty ? 'unknown' : field.measurementMethod;
      cropArea[crop] = (cropArea[crop] ?? 0) + field.area;
      statusArea[status] = (statusArea[status] ?? 0) + field.area;
      measurementCount[method] = (measurementCount[method] ?? 0) + 1;
    }

    return FarmMapSummary(
      fields: visible,
      totalArea: totalArea,
      cropArea: Map.unmodifiable(cropArea),
      statusArea: Map.unmodifiable(statusArea),
      measurementCount: Map.unmodifiable(measurementCount),
    );
  }

  List<String> cropOptions(Iterable<FieldModel> fields) =>
      <String>{'Tất cả', ...fields.map((field) => field.crop).where((value) => value.isNotEmpty)}.toList();

  List<String> statusOptions(Iterable<FieldModel> fields) =>
      <String>{'Tất cả', ...fields.map((field) => field.status).where((value) => value.isNotEmpty)}.toList();
}
