import '../../../../core/identity/domain/business_reference_code.dart';
import '../domain/finance_document.dart';

/// Shared display/export filter. Dates use the calendar date on the document.
class FinanceDocumentFilter {
  const FinanceDocumentFilter({
    this.query = '',
    this.kind,
    this.from,
    this.to,
    this.parcel = 'all',
  });
  final String query;
  final BusinessDocumentKind? kind;
  final DateTime? from;
  final DateTime? to;
  final String parcel;
  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
  void validate() {
    if (kind != null &&
        kind != BusinessDocumentKind.receipt &&
        kind != BusinessDocumentKind.payment) {
      throw const FormatException('Unsupported finance document kind.');
    }
    if (from != null && to != null && _day(from!).isAfter(_day(to!))) {
      throw const FormatException('Invalid date range.');
    }
    if (parcel != 'all' &&
        parcel != 'general' &&
        !(parcel.startsWith('parcel:') &&
            parcel.substring(7).trim().isNotEmpty)) {
      throw const FormatException('Invalid parcel filter.');
    }
  }

  bool matches(FinanceDocument document) {
    final day = _day(document.occurredAt);
    final text = query.trim().toLowerCase();
    return (parcel == 'all' ||
            (parcel == 'general' && document.parcelId == null) ||
            (parcel.startsWith('parcel:') &&
                document.parcelId == parcel.substring(7))) &&
        (from == null || !day.isBefore(_day(from!))) &&
        (to == null || !day.isAfter(_day(to!))) &&
        (kind == null || document.kind == kind) &&
        (text.isEmpty ||
            document.code.toLowerCase().contains(text) ||
            document.category.toLowerCase().contains(text) ||
            (document.description ?? '').toLowerCase().contains(text));
  }
}
