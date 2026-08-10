import 'package:flutter/foundation.dart';

import '../models/harvest_record_model.dart';
import '../services/harvest_database.dart';

class HarvestProvider extends ChangeNotifier {
  final HarvestDatabase _database;
  final Map<String, List<HarvestRecordModel>> _records = {};
  bool _loading = false;

  HarvestProvider({HarvestDatabase? database}) : _database = database ?? HarvestDatabase();

  bool get isLoading => _loading;
  List<HarvestRecordModel> recordsForSeason(String seasonId) => List.unmodifiable(_records[seasonId] ?? const []);
  List<HarvestRecordModel> get allRecords => List.unmodifiable(_records.values.expand((items) => items));

  Future<void> loadForSeasons(Iterable<String> seasonIds) async {
    final ids = seasonIds.toSet();
    _loading = true;
    notifyListeners();
    try {
      final entries = await Future.wait(
        ids.map((seasonId) async => MapEntry(seasonId, await _database.getBySeason(seasonId))),
      );
      for (final entry in entries) {
        _records[entry.key] = entry.value;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadForSeason(String seasonId) async {
    _loading = true;
    notifyListeners();
    try {
      _records[seasonId] = await _database.getBySeason(seasonId);
    } finally {
      _loading = false;
      notifyListeners();
    }
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
