import 'package:flutter/foundation.dart';

import '../models/production_cost_model.dart';
import '../services/production_cost_database.dart';

class ProductionCostProvider extends ChangeNotifier {
  final ProductionCostDatabase _database;
  final Map<String, List<ProductionCostModel>> _records = {};
  bool _loading = false;

  ProductionCostProvider({ProductionCostDatabase? database})
      : _database = database ?? ProductionCostDatabase();

  bool get isLoading => _loading;

  List<ProductionCostModel> recordsForSeason(String seasonId) =>
      List.unmodifiable(_records[seasonId] ?? const []);

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

  Future<void> save(ProductionCostModel record) async {
    await _database.upsert(record);
    final current = [...recordsForSeason(record.seasonId)];
    final index = current.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      current.insert(0, record);
    } else {
      current[index] = record;
    }
    current.sort((a, b) => b.date.compareTo(a.date));
    _records[record.seasonId] = current;
    notifyListeners();
  }

  Future<void> delete(ProductionCostModel record) async {
    await _database.delete(record.id);
    _records[record.seasonId] = recordsForSeason(record.seasonId)
        .where((item) => item.id != record.id)
        .toList(growable: false);
    notifyListeners();
  }

  double totalCost(String seasonId) => recordsForSeason(seasonId)
      .fold(0, (sum, record) => sum + record.amount);

  Map<ProductionCostCategory, double> byCategory(String seasonId) {
    final result = <ProductionCostCategory, double>{};
    for (final record in recordsForSeason(seasonId)) {
      result[record.category] = (result[record.category] ?? 0) + record.amount;
    }
    return result;
  }
}
