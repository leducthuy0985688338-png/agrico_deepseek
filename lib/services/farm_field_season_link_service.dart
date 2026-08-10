import '../models/field_model.dart';
import '../models/production_season_model.dart';

class FarmFieldSeasonLinkRow {
  final FieldModel field;
  final List<ProductionSeasonModel> seasons;

  const FarmFieldSeasonLinkRow({
    required this.field,
    required this.seasons,
  });

  int get seasonCount => seasons.length;

  int get activeSeasonCount =>
      seasons.where((season) => season.status == 'Đang sản xuất').length;

  double get plannedSeasonArea =>
      seasons.fold<double>(0, (sum, season) => sum + season.plannedArea);

  ProductionSeasonModel? get currentSeason {
    for (final season in seasons) {
      if (season.status == 'Đang sản xuất') return season;
    }
    return seasons.isEmpty ? null : seasons.last;
  }
}

class FarmFieldSeasonLinkService {
  const FarmFieldSeasonLinkService();

  List<FarmFieldSeasonLinkRow> linkFieldsToSeasons({
    required Iterable<FieldModel> fields,
    required Iterable<ProductionSeasonModel> seasons,
  }) {
    final seasonsByField = <String, List<ProductionSeasonModel>>{};
    for (final season in seasons) {
      seasonsByField.putIfAbsent(season.fieldId, () => <ProductionSeasonModel>[]).add(season);
    }

    return fields
        .map(
          (field) => FarmFieldSeasonLinkRow(
            field: field,
            seasons: List<ProductionSeasonModel>.unmodifiable(
              seasonsByField[field.id] ?? const <ProductionSeasonModel>[],
            ),
          ),
        )
        .toList(growable: false);
  }

  List<FarmFieldSeasonLinkRow> onlyActive({
    required Iterable<FieldModel> fields,
    required Iterable<ProductionSeasonModel> seasons,
  }) {
    return linkFieldsToSeasons(fields: fields, seasons: seasons)
        .where((row) => row.activeSeasonCount > 0)
        .toList(growable: false);
  }

  double totalPlannedSeasonArea(Iterable<FarmFieldSeasonLinkRow> rows) =>
      rows.fold<double>(0, (sum, row) => sum + row.plannedSeasonArea);
}
