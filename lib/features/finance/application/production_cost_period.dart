/// Filters the calendar date recorded on each document, inclusively.
class ProductionCostPeriod {
  const ProductionCostPeriod({this.from, this.to});
  final DateTime? from;
  final DateTime? to;
  bool get isAllDates => from == null && to == null;

  static DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  void validate() {
    if (from != null && to != null && _day(from!).isAfter(_day(to!))) {
      throw const FormatException('Invalid production cost date range.');
    }
  }

  bool contains(DateTime value) {
    final day = _day(value);
    return (from == null || !day.isBefore(_day(from!))) &&
        (to == null || !day.isAfter(_day(to!)));
  }
}
