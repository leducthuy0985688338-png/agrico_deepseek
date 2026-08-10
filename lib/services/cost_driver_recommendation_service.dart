import '../models/production_cost_model.dart';
import 'season_cost_driver_analysis_service.dart';

enum CostRecommendationLevel { low, medium, high, critical }

class CostDriverRecommendation {
  final SeasonCostDriverChange driver;
  final CostRecommendationLevel level;
  final String action;

  const CostDriverRecommendation({
    required this.driver,
    required this.level,
    required this.action,
  });

  double get absoluteChange => driver.absoluteChange;
  double get changeRate => driver.changeRate;
}

class CostDriverRecommendationService {
  const CostDriverRecommendationService();

  List<CostDriverRecommendation> buildRecommendations(
    SeasonCostDriverAnalysis analysis,
  ) {
    final recommendations = analysis.increasingDrivers
        .map(_buildRecommendation)
        .where((item) => item.absoluteChange > 0.000001)
        .toList()
      ..sort((a, b) {
        final levelCompare = _score(b.level).compareTo(_score(a.level));
        if (levelCompare != 0) return levelCompare;
        return b.absoluteChange.compareTo(a.absoluteChange);
      });
    return recommendations;
  }

  CostDriverRecommendation _buildRecommendation(SeasonCostDriverChange driver) {
    final rate = driver.changeRate;
    final level = rate >= 0.50 || driver.absoluteChange >= 10000000
        ? CostRecommendationLevel.critical
        : rate >= 0.25 || driver.absoluteChange >= 5000000
            ? CostRecommendationLevel.high
            : rate >= 0.10 || driver.absoluteChange >= 1000000
                ? CostRecommendationLevel.medium
                : CostRecommendationLevel.low;

    return CostDriverRecommendation(
      driver: driver,
      level: level,
      action: _actionFor(driver.category),
    );
  }

  int _score(CostRecommendationLevel level) {
    switch (level) {
      case CostRecommendationLevel.low:
        return 1;
      case CostRecommendationLevel.medium:
        return 2;
      case CostRecommendationLevel.high:
        return 3;
      case CostRecommendationLevel.critical:
        return 4;
    }
  }

  String _actionFor(ProductionCostCategory category) {
    switch (category) {
      case ProductionCostCategory.material:
        return 'Kiểm tra đơn giá mua, định mức/ha và tỷ lệ hao hụt vật tư.';
      case ProductionCostCategory.labor:
        return 'Đối chiếu ngày công với khối lượng thực hiện và năng suất theo khu vực.';
      case ProductionCostCategory.machine:
        return 'Đối chiếu giờ máy, diện tích thực hiện và thời gian chạy rỗng.';
      case ProductionCostCategory.fuel:
        return 'Đối chiếu nhiên liệu với giờ máy, diện tích và định mức tiêu hao.';
    }
  }
}
