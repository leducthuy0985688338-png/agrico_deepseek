import '../../../core/identity/domain/business_reference_code.dart';

/// A persisted finance document; ID and human-readable code are distinct.
class FinanceDocument {
  const FinanceDocument({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.kind,
    required this.occurredAt,
    required this.amountMinor,
    required this.currency,
    required this.category,
    this.parcelId,
    this.description,
  });

  final String id;
  final String organizationId;
  final String code;
  final BusinessDocumentKind kind;
  final DateTime occurredAt;
  final int amountMinor;
  final String currency;
  final String category;
  final String? parcelId;
  final String? description;
}
