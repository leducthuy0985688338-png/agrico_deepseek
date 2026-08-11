import 'package:agrico_deepseek/models/production_log_model.dart';
import 'package:agrico_deepseek/providers/production_log_provider.dart';
import 'package:agrico_deepseek/services/production_log_database.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProductionLogDatabase extends ProductionLogDatabase {
  List<ProductionLogModel> persisted = const [];

  @override
  Future<void> replaceAll(List<ProductionLogModel> logs) async {
    persisted = List.unmodifiable(logs);
  }
}

void main() {
  test('production log cloud round trip keeps operational details', () {
    final source = ProductionLogModel(
      id: 'NK-CLOUD',
      seasonId: 'VU-CLOUD',
      fieldId: 'LO-CLOUD',
      date: DateTime.utc(2026, 11, 2, 7, 30),
      activityType: 'Gieo trồng',
      title: 'Gieo giống lạc L14',
      quantity: 185.5,
      unit: 'kg',
      cost: 7420000,
      worker: 'Nguyễn Văn An',
      notes: 'Độ sâu gieo 4 cm',
    );

    final restored = ProductionLogModel.fromJson(source.toJson());

    expect(restored.id, source.id);
    expect(restored.seasonId, source.seasonId);
    expect(restored.fieldId, source.fieldId);
    expect(restored.date, source.date);
    expect(restored.activityType, source.activityType);
    expect(restored.title, source.title);
    expect(restored.quantity, source.quantity);
    expect(restored.unit, source.unit);
    expect(restored.cost, source.cost);
    expect(restored.worker, source.worker);
    expect(restored.notes, source.notes);
  });

  test('log restore replaces state, deduplicates, and ignores empty cloud',
      () async {
    final database = FakeProductionLogDatabase();
    final provider = ProductionLogProvider(database: database);
    final older = ProductionLogModel(
      id: 'NK-01',
      seasonId: 'VU-01',
      fieldId: 'LO-01',
      date: DateTime.utc(2026, 10, 1),
      activityType: 'Làm đất',
      title: 'Cày lần một',
      quantity: 4,
      unit: 'ha',
      cost: 3200000,
      worker: 'Tổ máy 1',
    );
    final newer = ProductionLogModel(
      id: 'NK-02',
      seasonId: 'VU-01',
      fieldId: 'LO-01',
      date: DateTime.utc(2026, 10, 4),
      activityType: 'Bón phân',
      title: 'Bón lót',
      quantity: 800,
      unit: 'kg',
      cost: 9600000,
      worker: 'Tổ sản xuất 2',
    );

    await provider.restoreFromCloud(logs: [older, newer, newer]);

    expect(provider.allLogs, hasLength(2));
    expect(
      provider.logsForSeason('VU-01').map((item) => item.id),
      ['NK-02', 'NK-01'],
    );
    expect(
      database.persisted.map((item) => item.id).toSet(),
      {'NK-01', 'NK-02'},
    );
    expect(provider.totalCost('VU-01'), 12800000);

    final idsAfterRestore =
        provider.allLogs.map((item) => item.id).toList(growable: false);
    await provider.restoreFromCloud(logs: const []);

    expect(provider.allLogs.map((item) => item.id), idsAfterRestore);
    expect(database.persisted, hasLength(2));
  });
}
