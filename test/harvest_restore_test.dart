import 'package:agrico_deepseek/models/harvest_record_model.dart';
import 'package:agrico_deepseek/providers/harvest_provider.dart';
import 'package:agrico_deepseek/services/harvest_database.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHarvestDatabase extends HarvestDatabase {
  List<HarvestRecordModel> persisted = const [];

  @override
  Future<void> replaceAll(List<HarvestRecordModel> records) async {
    persisted = List.unmodifiable(records);
  }
}

void main() {
  test('harvest cloud round trip keeps yield and commercial details', () {
    final source = HarvestRecordModel(
      id: 'TH-CLOUD',
      seasonId: 'VU-CLOUD',
      fieldId: 'LO-CLOUD',
      date: DateTime.utc(2027, 2, 18, 9, 15),
      quantity: 18450.5,
      unit: 'kg',
      moisturePercent: 12.8,
      sellingPrice: 28500,
      revenue: 525839250,
      notes: 'Cân tại kho trung tâm',
    );

    final restored = HarvestRecordModel.fromJson(source.toJson());

    expect(restored.id, source.id);
    expect(restored.seasonId, source.seasonId);
    expect(restored.fieldId, source.fieldId);
    expect(restored.date, source.date);
    expect(restored.quantity, source.quantity);
    expect(restored.unit, source.unit);
    expect(restored.moisturePercent, source.moisturePercent);
    expect(restored.sellingPrice, source.sellingPrice);
    expect(restored.revenue, source.revenue);
    expect(restored.notes, source.notes);
  });

  test('harvest restore replaces state, deduplicates, and ignores empty cloud',
      () async {
    final database = FakeHarvestDatabase();
    final provider = HarvestProvider(database: database);
    final older = HarvestRecordModel(
      id: 'TH-01',
      seasonId: 'VU-01',
      fieldId: 'LO-01',
      date: DateTime.utc(2027, 2, 15),
      quantity: 100,
      sellingPrice: 20000,
    );
    final newer = HarvestRecordModel(
      id: 'TH-02',
      seasonId: 'VU-01',
      fieldId: 'LO-01',
      date: DateTime.utc(2027, 2, 18),
      quantity: 120,
      sellingPrice: 30000,
      revenue: 3600000,
    );

    await provider.restoreFromCloud(records: [older, newer, newer]);

    expect(provider.allRecords, hasLength(2));
    expect(
      provider.recordsForSeason('VU-01').map((item) => item.id),
      ['TH-02', 'TH-01'],
    );
    expect(
      database.persisted.map((item) => item.id).toSet(),
      {'TH-01', 'TH-02'},
    );
    expect(provider.totalQuantity('VU-01'), 220);
    expect(provider.totalRevenue('VU-01'), 5600000);

    final idsAfterRestore =
        provider.allRecords.map((item) => item.id).toList(growable: false);
    await provider.restoreFromCloud(records: const []);

    expect(provider.allRecords.map((item) => item.id), idsAfterRestore);
    expect(database.persisted, hasLength(2));
  });
}
