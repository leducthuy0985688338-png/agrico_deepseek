import '../../../../core/identity/domain/business_reference_code.dart';
import '../domain/finance_document.dart';
import '../../inventory/domain/entities/exact_decimal.dart';

class FinanceCurrencyTotal {
  const FinanceCurrencyTotal({
    required this.currency,
    required this.receiptsText,
    required this.paymentsText,
  });
  final String currency, receiptsText, paymentsText;
  String get balanceText =>
      (ExactDecimal.parse(receiptsText) - ExactDecimal.parse(paymentsText))
          .toString();
  int get receiptsMinor => int.parse(receiptsText);
  int get paymentsMinor => int.parse(paymentsText);
  int get balanceMinor => int.parse(balanceText);
}

class FinanceDocumentSummary {
  const FinanceDocumentSummary(this.store);
  final FinanceDocumentStore store;
  Future<List<FinanceCurrencyTotal>> byOrganization(String id) async {
    if (id.trim().isEmpty)
      throw const FormatException('Organization required.');
    return fromDocuments(await store.listByOrganization(id), id);
  }

  static List<FinanceCurrencyTotal> fromDocuments(
    Iterable<FinanceDocument> documents,
    String id,
  ) {
    if (id.trim().isEmpty)
      throw const FormatException('Organization required.');
    final receipts = <String, ExactDecimal>{},
        payments = <String, ExactDecimal>{};
    for (final d in documents) {
      if (d.organizationId != id) throw StateError('Wrong organization.');
      if (d.kind != BusinessDocumentKind.receipt &&
          d.kind != BusinessDocumentKind.payment)
        throw StateError('Unsupported finance document kind.');
      final map = d.kind == BusinessDocumentKind.receipt ? receipts : payments;
      map[d.currency] =
          (map[d.currency] ?? ExactDecimal.parse('0')) +
          ExactDecimal.parse(d.amountText);
    }
    final currencies = {...receipts.keys, ...payments.keys}.toList()..sort();
    return [
      for (final c in currencies)
        FinanceCurrencyTotal(
          currency: c,
          receiptsText: (receipts[c] ?? ExactDecimal.parse('0')).toString(),
          paymentsText: (payments[c] ?? ExactDecimal.parse('0')).toString(),
        ),
    ];
  }
}
