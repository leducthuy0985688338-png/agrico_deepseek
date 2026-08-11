import 'package:agrico_deepseek/models/production_season_model.dart';
import 'package:agrico_deepseek/providers/production_season_provider.dart';
import 'package:agrico_deepseek/services/production_season_database.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProductionSeasonDatabase extends ProductionSeasonDatabase {
  List<ProductionSeasonModel> persisted = const [];

  @override
  Future<void> replaceAll(List<ProductionSeasonModel> seasons) async {
    persisted = List.unmodifiable(seasons);
  }
}

void main() {
  test('production season cloud round trip keeps planning details', () {
    final source = ProductionSeasonModel(
      id: 'VU-CLOUD',
      fieldId: 'LO-CLOUD',
      name: 'Vụ lạc 2026',
      crop: 'Cây lạc',
      variety: 'L14',
      startDate: DateTime.utc(2026, 10, 15),
      expectedHarvestDate: DateTime.utc(2027, 2, 10),
      status: 'Đang sản xuất',
      plannedArea: 12543.75,
      notes: 'Ưu tiên tưới tiết kiệm',
    );

    final restored = ProductionSeasonModel.fromJson(source.toJson());

    expect(restored.id, source.id);
    expect(restored.fieldId, source.fieldId);
    expect(restored.name, source.name);
    expect(restored.crop, source.crop);
    expect(restored.variety, source.variety);
    expect(restored.startDate, source.startDate);
    expect(restored.expectedHarvestDate, source.expectedHarvestDate);
    expect(restored.status, source.status);
    expect(restored.plannedArea, source.plannedArea);
    expect(restored.notes, source.notes);
  });

  test('season restore replaces state, deduplicates, and ignores empty cloud',
      () async {
    final database = FakeProductionSeasonDatabase();
    final provider = ProductionSeasonProvider(database: database);
    final older = ProductionSeasonModel(
      id: 'VU-01',
      fieldId: 'LO-01',
      name: 'Vụ cũ',
      crop: 'Cây lạc',
      variety: 'L14',
      startDate: DateTime.utc(2026, 5, 1),
      expectedHarvestDate: DateTime.utc(2026, 8, 20),
      status: 'Đã hoàn thành',
      plannedArea: 10000,
    );
    final newer = ProductionSeasonModel(
      id: 'VU-02',
      fieldId: 'LO-01',
      name: 'Vụ mới',
      crop: 'Cây lạc',
      variety: 'L27',
      startDate: DateTime.utc(2026, 10, 1),
      expectedHarvestDate: DateTime.utc(2027, 1, 25),
      status: 'Đang sản xuất',
      plannedArea: 12000,
    );

    await provider.restoreFromCloud(seasons: [older, newer, newer]);

    expect(provider.allSeasons, hasLength(2));
    expect(provider.seasonsForField('LO-01').map((item) => item.id),
        ['VU-02', 'VU-01']);
    expect(database.persisted.map((item) => item.id).toSet(),
        {'VU-01', 'VU-02'});

    final idsAfterRestore =
        provider.allSeasons.map((item) => item.id).toList(growable: false);
    await provider.restoreFromCloud(seasons: const []);

    expect(provider.allSeasons.map((item) => item.id), idsAfterRestore);
    expect(database.persisted, hasLength(2));
  });
}
