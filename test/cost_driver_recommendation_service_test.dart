import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/services/cost_driver_recommendation_service.dart';
import 'package:agrico_deepseek/services/season_cost_driver_analysis_service.dart';

void main() {
  test('ranks critical driver before lower priority drivers', () {
    const analysis = SeasonCostDriverAnalysis(
      currentSeasonId: 'current',
      previousSeasonId: 'previous',
      currentTotal: 200,
      previousTotal: 100,
      categories: [],
      drivers: [
        SeasonCostDriverChange(
          label: 'Phân bón',
          category: ProductionCostCategory.material,
          currentAmount: 180,
          previousAmount: 100,
        ),
        SeasonCostDriverChange(
          label: 'Dầu diesel',
          category: ProductionCostCategory.fuel,
          currentAmount: 30,
          previousAmount: 29,
        ),
      ],
    );

    final result = const CostDriverRecommendationService()
        .buildRecommendations(analysis);

    expect(result, hasLength(2));
    expect(result.first.driver.label, 'Phân bón');
    expect(result.first.level, CostRecommendationLevel.critical);
    expect(result.first.action, contains('định mức'));
    expect(result.last.level, CostRecommendationLevel.low);
  });
}
