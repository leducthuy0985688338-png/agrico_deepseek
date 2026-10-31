import '../../inventory/domain/entities/exact_decimal.dart';
import '../../../core/identity/domain/business_reference_code.dart';
import '../../../core/permissions/authorization.dart';

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
    this.amountScale = 0,
    this.isSettlement = false,
    this.isFinancing = false,
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
  final int amountScale;
  final bool isSettlement;
  final bool isFinancing;
  String get amountText {
    if (amountScale < 0 || amountScale > 6)
      throw const FormatException('Invalid money scale.');
    var digits = amountMinor.abs().toString().padLeft(amountScale + 1, '0');
    if (amountScale > 0)
      digits =
          '${digits.substring(0, digits.length - amountScale)}.${digits.substring(digits.length - amountScale)}';
    return ExactDecimal.parse(
      '${amountMinor < 0 ? '-' : ''}$digits',
    ).toString();
  }

  final String currency;
  final String category;
  final String? parcelId;
  final String? description;
}

/// Storage boundary used by the finance UI.
abstract interface class FinanceDocumentStore {
  Future<FinanceDocument> create({
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
  });

  Future<List<FinanceDocument>> listByOrganization(String organizationId);
}

abstract interface class PendingFinanceDocumentStore {
  Future<FinanceDocument> createPendingFinance({
    required AuthorizationSubject creator,
    required AuthorizationSubject? Function() currentSubject,
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
    String? beneficiaryPartyId,
  });
}
