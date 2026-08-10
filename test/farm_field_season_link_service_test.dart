import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/models/production_season_model.dart';
import 'package:agrico_deepseek/services/farm_field_season_link_service.dart';

void main() {
  const service = FarmFieldSeasonLinkService();

  final fields = <FieldModel>[
    FieldModel(
      id: 'F1',
      name: 'Thửa 01',
      area: 10000,
      crop: 'Lạc',
      status: 'Đang sản xuất',
    ),
    FieldModel(
      id: 'F2',
      name: 'Thửa 02',
      area: 20000,
      crop: 'Lạc',
      status: 'Đang sản xuất',
    ),
  ];

  final seasons = <ProductionSeasonModel>[
    ProductionSeasonModel(
      id: 'S1',
      fieldId: 'F1',
      name: 'Vụ Lạc 2026',
      crop: 'Lạc',
      variety: 'Lạc đỏ',
      startDate: DateTime(2026, 1, 1),
      expectedHarvestDate: DateTime(2026, 5, 1),
      status: 'Đang sản xuất',
      plannedArea: 10000,
    ),
    ProductionSeasonModel(
      id: 'S2',
      fieldId: 'F1',
      name: 'Vụ Lạc 2025',
      crop: 'Lạc',
      variety: 'Lạc đỏ',
      startDate: DateTime(2025, 1, 1),
      expectedHarvestDate: DateTime(2025, 5, 1),
      status: 'Đã hoàn thành',
      plannedArea: 9500,
    ),
  ];

  test('links seasons to their field', () {
    final rows = service.linkFieldsToSeasons(
      fields: fields,
      seasons: seasons,
    );

    expect(rows, hasLength(2));
    expect(rows[0].seasonCount, 2);
    expect(rows[0].activeSeasonCount, 1);
    expect(rows[0].plannedSeasonArea, 19500);
    expect(rows[0].currentSeason?.id, 'S1');
    expect(rows[1].seasonCount, 0);
  });

  test('filters fields that have an active production season', () {
    final rows = service.onlyActive(
      fields: fields,
      seasons: seasons,
    );

    expect(rows, hasLength(1));
    expect(rows.single.field.id, 'F1');
  });

  test('sums planned season area across linked rows', () {
    final rows = service.linkFieldsToSeasons(
      fields: fields,
      seasons: seasons,
    );

    expect(service.totalPlannedSeasonArea(rows), 19500);
  });
}
