import '../../inventory/domain/entities/exact_decimal.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney, MoneyRounding;
export '../../personnel/domain/personnel.dart' show MoneyRounding;
export '../../inventory/domain/entities/exact_decimal.dart';

enum TradeKind { harvest, sale, purchase, expense }

abstract final class TradeMath {
  static int units(String qty) {
    final d = ExactDecimal.parse(qty, maxScale: 6);
    final n = d.coefficient * BigInt.from(10).pow(6 - d.scale);
    if (n <= BigInt.zero || n > BigInt.from(9007199254740991)) {
      throw const FormatException('Invalid exact quantity.');
    }
    return n.toInt();
  }

  static int money(String text, {bool positive = false}) {
    final d = ExactDecimal.parse(text, maxScale: 0);
    if (d.isNegative ||
        (positive && d.coefficient == BigInt.zero) ||
        d.coefficient > BigInt.from(9007199254740991)) {
      throw const FormatException('Whole VND/LAK amount outside range.');
    }
    return d.coefficient.toInt();
  }

  static String total(Iterable<String> values) => LaborMoney.sum(values);
  static String subtract(String a, String b) => LaborMoney.minus(a, b);
  static String bill(String raw, MoneyRounding rounding) =>
      LaborMoney.fraction(raw, 1, 1, 0, rounding);
  static List<String> lineAmounts(TradeDraft d) {
    final raw = d.lines.map((l) => ExactDecimal.parse(l.rawAmount)).toList();
    final scale = raw.fold<int>(0, (s, v) => v.scale > s ? v.scale : s);
    final weights = raw
        .map((v) => v.coefficient * BigInt.from(10).pow(scale - v.scale))
        .toList();
    final divisor = weights.fold(BigInt.zero, (s, v) => s + v);
    final total = BigInt.parse(d.billed);
    if (divisor == BigInt.zero) return List.filled(raw.length, '0');
    final parts = weights.map((v) => total * v ~/ divisor).toList();
    final order = List.generate(parts.length, (i) => i)
      ..sort((a, b) {
        final c = (total * weights[b] % divisor).compareTo(
          total * weights[a] % divisor,
        );
        return c == 0 ? a.compareTo(b) : c;
      });
    final remain = (total - parts.fold(BigInt.zero, (s, v) => s + v)).toInt();
    for (var i = 0; i < remain; i++) {
      parts[order[i]] += BigInt.one;
    }
    return parts.map((v) => v.toString()).toList();
  }

  static String day() => LaborMoney.day(DateTime.now());
  static DateTime instant(String day) =>
      DateTime.parse('${day}T12:00:00+07:00').toUtc();
  static void date(String day) => LaborMoney.date(day);
  static void requiredText(String value) {
    if (value.trim().isEmpty || value.length > 2000) {
      throw const FormatException('Required text.');
    }
  }
}

class TradeLine {
  const TradeLine({
    required this.ref,
    required this.quantity,
    required this.price,
    this.issuePrice,
    this.label = '',
    this.zeroConfirmed = false,
  });
  final String ref, quantity, price, label;
  final String? issuePrice;
  final bool zeroConfirmed;
  int get units => TradeMath.units(quantity);
  String get rawAmount =>
      (ExactDecimal.parse(quantity) * ExactDecimal.parse(price)).toString();
  void validate(String currency) {
    TradeMath.units(quantity);
    ExactDecimal.validatePrice(price, currency);
    if (ExactDecimal.parse(price).coefficient == BigInt.zero &&
        !zeroConfirmed) {
      throw const FormatException('Explicit zero-price confirmation required.');
    }
  }

  Map<String, dynamic> toJson() => {
    'issuePrice': issuePrice,
    'ref': ref,
    'quantity': quantity,
    'price': price,
    'label': label,
    'zeroConfirmed': zeroConfirmed,
  };
  factory TradeLine.fromJson(Map<String, dynamic> j) => TradeLine(
    issuePrice: j['issuePrice'] as String?,
    ref: j['ref'] as String,
    quantity: j['quantity'] as String,
    price: j['price'] as String,
    label: j['label'] as String,
    zeroConfirmed: j['zeroConfirmed'] as bool,
  );
}

class TradeDraft {
  const TradeDraft({
    required this.id,
    required this.kind,
    required this.day,
    required this.currency,
    required this.rounding,
    required this.lines,
    this.partyId,
    this.planId,
    this.dueOn,
    this.expenseTreatment,
    this.reference = '',
    this.note = '',
  });
  final String id, day, currency, reference, note;
  final String? partyId, planId, dueOn, expenseTreatment;
  final TradeKind kind;
  final MoneyRounding rounding;
  final List<TradeLine> lines;
  String get rawTotal => TradeMath.total(lines.map((l) => l.rawAmount));
  String get billed => TradeMath.bill(rawTotal, rounding);
  void validate() {
    TradeMath.requiredText(id);
    TradeMath.date(day);
    if (!{'VND', 'LAK'}.contains(currency) ||
        lines.isEmpty ||
        lines.length > 100) {
      throw const FormatException('Invalid document.');
    }
    for (final l in lines) {
      l.validate(currency);
      if (kind == TradeKind.sale) {
        ExactDecimal.validatePrice(l.issuePrice ?? '', currency);
        if (ExactDecimal.parse(l.issuePrice!).coefficient == BigInt.zero &&
            !l.zeroConfirmed) {
          throw const FormatException('Confirm zero issue price.');
        }
      }
      if (kind != TradeKind.expense) {
        TradeMath.requiredText(l.ref);
      } else {
        TradeMath.requiredText(l.label);
      }
    }
    if (kind == TradeKind.harvest) {
      TradeMath.requiredText(planId ?? '');
      if (partyId != null || dueOn != null) {
        throw const FormatException('Harvest is not a financial invoice.');
      }
    } else {
      TradeMath.requiredText(partyId ?? '');
      TradeMath.date(dueOn ?? '');
      if (dueOn!.compareTo(day) < 0) {
        throw const FormatException('Due date before document.');
      }
      if (planId != null &&
          !(kind == TradeKind.expense &&
              expenseTreatment == 'directProduction')) {
        throw const FormatException('Plan comes from harvest lot.');
      }
    }
    if (kind == TradeKind.purchase || kind == TradeKind.expense) {
      TradeMath.requiredText(reference);
    }
    if (kind == TradeKind.expense &&
        !{
          'periodExpense',
          'includedInProduction',
          'directProduction',
          'commonProduction',
        }.contains(expenseTreatment)) {
      throw const FormatException('Choose expense treatment explicitly.');
    }
    if (kind == TradeKind.expense && expenseTreatment == 'directProduction') {
      TradeMath.requiredText(planId ?? '');
    }
    TradeMath.money(billed);
    if (note.length > 2000 || reference.length > 200) {
      throw const FormatException('Text too long.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'day': day,
    'currency': currency,
    'rounding': rounding.name,
    'lines': lines.map((l) => l.toJson()).toList(),
    'expenseTreatment': expenseTreatment,
    'partyId': partyId,
    'planId': planId,
    'dueOn': dueOn,
    'reference': reference,
    'note': note,
  };
  factory TradeDraft.fromJson(Map<String, dynamic> j) => TradeDraft(
    id: j['id'] as String,
    kind: TradeKind.values.byName(j['kind'] as String),
    day: j['day'] as String,
    currency: j['currency'] as String,
    rounding: MoneyRounding.values.byName(j['rounding'] as String),
    lines: (j['lines'] as List)
        .map((l) => TradeLine.fromJson(Map<String, dynamic>.from(l as Map)))
        .toList(),
    expenseTreatment: j['expenseTreatment'] as String?,
    partyId: j['partyId'] as String?,
    planId: j['planId'] as String?,
    dueOn: j['dueOn'] as String?,
    reference: j['reference'] as String,
    note: j['note'] as String,
  );
}

class TradeRecord {
  const TradeRecord(
    this.draft,
    this.code,
    this.status,
    this.revision,
    this.snapshots,
    this.paid,
  );
  final TradeDraft draft;
  final String code, status, paid;
  final int revision;
  final Map<String, dynamic> snapshots;
  String get balance => status == 'posted' && draft.kind != TradeKind.harvest
      ? TradeMath.subtract(draft.billed, paid)
      : '0';
}

class FinishedLot {
  const FinishedLot({
    required this.id,
    required this.farm,
    required this.itemId,
    required this.planId,
    required this.harvestId,
    required this.day,
    required this.originalUnits,
    required this.stockUnits,
    required this.price,
    required this.currency,
    required this.code,
    required this.itemName,
    required this.unit,
  });
  final String id,
      farm,
      itemId,
      planId,
      harvestId,
      day,
      price,
      currency,
      code,
      itemName,
      unit;
  final int originalUnits, stockUnits;
  String get quantity => ExactDecimal.quantityFromUnits(stockUnits).toString();
}

class TradePayment {
  const TradePayment({
    required this.id,
    required this.documentId,
    required this.financeId,
    required this.amount,
    required this.day,
    required this.reference,
    required this.currency,
    required this.reversed,
    required this.financeCode,
  });
  final String id,
      documentId,
      financeId,
      amount,
      day,
      reference,
      currency,
      financeCode;
  final bool reversed;
}

abstract interface class TradeRepository {
  Future<List<TradeRecord>> documents(String farm);
  Future<List<FinishedLot>> lots(String farm);
  Future<List<TradePayment>> payments(String farm);
  Future<List<Map<String, Object?>>> cashBook(String farm);
  Future<List<Map<String, Object?>>> choices(String farm, String kind);
  Future<void> create(String farm, TradeDraft draft, String actor);
  Future<void> post(String farm, String id, int revision, String actor);
  Future<void> voidDocument(
    String farm,
    String id,
    int revision,
    String day,
    String reason,
    String actor,
  );
  Future<void> settle(
    String farm,
    String id,
    String documentId,
    String amount,
    String currency,
    String day,
    String reference,
    String actor,
  );
  Future<void> reversePayment(
    String farm,
    String paymentId,
    String reversalId,
    String day,
    String reason,
    String actor,
  );
}
