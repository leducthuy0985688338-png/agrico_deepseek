/// Exact base-10 values. No binary floating point is used for money arithmetic.
class ExactDecimal implements Comparable<ExactDecimal> {
  ExactDecimal._(this.coefficient, this.scale);
  final BigInt coefficient;
  final int scale;
  factory ExactDecimal.parse(String text, {int maxScale = 12}) {
    if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(text) || text.length > 60) {
      throw const FormatException('Invalid decimal.');
    }
    final parts = text.split('.');
    final scale = parts.length == 2 ? parts[1].length : 0;
    if (scale > maxScale) {
      throw const FormatException('Too many decimal places.');
    }
    return ExactDecimal._(BigInt.parse(parts.join()), scale);
  }
  static BigInt _power(int n) => BigInt.from(10).pow(n);
  BigInt _at(int target) => coefficient * _power(target - scale);
  ExactDecimal operator +(ExactDecimal other) {
    final target = scale > other.scale ? scale : other.scale;
    return ExactDecimal._(_at(target) + other._at(target), target);
  }

  ExactDecimal operator -(ExactDecimal other) =>
      this + ExactDecimal._(-other.coefficient, other.scale);
  ExactDecimal operator *(ExactDecimal other) =>
      ExactDecimal._(coefficient * other.coefficient, scale + other.scale);
  @override
  int compareTo(ExactDecimal other) {
    final target = scale > other.scale ? scale : other.scale;
    return _at(target).compareTo(other._at(target));
  }

  bool get isNegative => coefficient.isNegative;
  @override
  String toString() {
    final negative = coefficient.isNegative ? '-' : '';
    var digits = coefficient.abs().toString().padLeft(scale + 1, '0');
    if (scale == 0) return '$negative$digits';
    digits =
        '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
    digits = digits
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '$negative$digits';
  }

  /// Up to six decimals and safe SQLite/web integer range.
  static int quantityUnits(num value) {
    if (!value.isFinite) throw const FormatException('Invalid quantity.');
    final decimal = ExactDecimal.parse(value.toString(), maxScale: 6);
    final units = decimal._at(6);
    if (units.abs() > BigInt.from(9007199254740991)) {
      throw const FormatException('Quantity exceeds exact storage range.');
    }
    return units.toInt();
  }

  static num quantityFromUnits(int value) =>
      value % 1000000 == 0 ? value ~/ 1000000 : value / 1000000;
  static void validatePrice(String text, String currency) {
    if (!{'VND', 'LAK'}.contains(currency) ||
        ExactDecimal.parse(text, maxScale: 6).isNegative) {
      throw const FormatException('Explicit VND/LAK price required.');
    }
  }
}
