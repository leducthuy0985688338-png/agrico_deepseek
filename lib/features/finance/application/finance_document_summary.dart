import '../../../../core/identity/domain/business_reference_code.dart';
import '../domain/finance_document.dart';

/// Totals for persisted v2 documents, kept separate for each currency.
class FinanceCurrencyTotal {
  const FinanceCurrencyTotal({
    required this.currency,
    required this.receiptsMinor,
    required this.paymentsMinor,
  });

  final String currency;
  final int receiptsMinor;
  final int paymentsMinor;
  int get balanceMinor => receiptsMinor - paymentsMinor;
}

class FinanceDocumentSummary {
  const FinanceDocumentSummary(this.store);

  final FinanceDocumentStore store;

  Future<List<FinanceCurrencyTotal>> byOrganization(
    String organizationId,
  ) async {
    if (organizationId.trim().isEmpty) {
      throw const FormatException('Organization is required.');
    }
    final documents = await store.listByOrganization(organizationId);
    return fromDocuments(documents, organizationId);
  }

  static List<FinanceCurrencyTotal> fromDocuments(
    Iterable<FinanceDocument> documents,
    String organizationId,
  ) {
    if (organizationId.trim().isEmpty) {
      throw const FormatException('Organization is required.');
    }
    final receipts = <String, int>{};
    final payments = <String, int>{};
    for (final document in documents) {
      if (document.organizationId != organizationId) {
        throw StateError('Finance document is outside the organization.');
      }
      if (document.kind == BusinessDocumentKind.receipt) {
        receipts.update(
          document.currency,
          (value) => value + document.amountMinor,
          ifAbsent: () => document.amountMinor,
        );
      } else if (document.kind == BusinessDocumentKind.payment) {
        payments.update(
          document.currency,
          (value) => value + document.amountMinor,
          ifAbsent: () => document.amountMinor,
        );
      } else {
        throw StateError('Unsupported finance document kind.');
      }
    }
    final currencies = {...receipts.keys, ...payments.keys}.toList()..sort();
    return List.unmodifiable([
      for (final currency in currencies)
        FinanceCurrencyTotal(
          currency: currency,
          receiptsMinor: receipts[currency] ?? 0,
          paymentsMinor: payments[currency] ?? 0,
        ),
    ]);
  }
}
