import 'package:flutter/foundation.dart';

import '../models/harvest_record_model.dart';
import '../services/harvest_database.dart';

class HarvestProvider extends ChangeNotifier {
  final HarvestDatabase _database;
  final Map<String, List<HarvestRecordModel>> _records = {};
  bool _loading = false;
  int _revision = 0;

  HarvestProvider({HarvestDatabase? database}) : _database = database ?? HarvestDatabase();

  bool get isLoading => _loading;
  List<HarvestRecordModel> recordsForSeason(String seasonId) => List.unmodifiable(_records[seasonId] ?? const []);
  List<HarvestRecordModel> get allRecords => List.unmodifiable(_records.values.expand((items) => items));

  Future<void> loadForSeasons(Iterable<String> seasonIds) async {
    final ids = seasonIds.toSet();
    final revision = _revision;
    _loading = true;
    notifyListeners();
    try {
      final entries = await Future.wait(
        ids.map(
          (seasonId) async =>
              MapEntry(seasonId, await _database.getBySeason(seasonId)),
        ),
      );
      if (revision != _revision) return;
      _records
        ..clear()
        ..addEntries(entries);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadForSeason(String seasonId) async {
    final revision = _revision;
    _loading = true;
    notifyListeners();
    try {
      final records = await _database.getBySeason(seasonId);
      if (revision == _revision) {
        _records[seasonId] = records;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> restoreFromCloud({
    required List<HarvestRecordModel> records,
  }) async {
    if (records.isEmpty) return;

    final restored = <String, HarvestRecordModel>{
      for (final record in records) record.id: record,
    }.values.toList(growable: false);

    final grouped = <String, List<HarvestRecordModel>>{};
    for (final record in restored) {
      (grouped[record.seasonId] ??= []).add(record);
    }
    for (final items in grouped.values) {
      items.sort((a, b) => b.date.compareTo(a.date));
    }

    await _database.replaceAll(restored);

    _revision++;
    _records
      ..clear()
      ..addAll(grouped);
    notifyListeners();
  }

  Future<void> save(HarvestRecordModel record) async {
    await _database.upsert(record);
    final current = [...recordsForSeason(record.seasonId)];
    final index = current.indexWhere((item) => item.id == record.id);
    if (index == -1) current.insert(0, record); else current[index] = record;
    current.sort((a, b) => b.date.compareTo(a.date));
    _records[record.seasonId] = current;
    notifyListeners();
  }

  Future<void> delete(HarvestRecordModel record) async {
    await _database.delete(record.id);
    _records[record.seasonId] = recordsForSeason(record.seasonId).where((item) => item.id != record.id).toList(growable: false);
    notifyListeners();
  }

  double totalQuantity(String seasonId) => recordsForSeason(seasonId).fold(0, (sum, item) => sum + item.quantity);
  double totalRevenue(String seasonId) => recordsForSeason(seasonId).fold(0, (sum, item) => sum + (item.revenue > 0 ? item.revenue : item.quantity * item.sellingPrice));
}
