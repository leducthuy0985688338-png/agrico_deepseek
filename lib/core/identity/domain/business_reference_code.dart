/// Human-readable reference for a dated business document.
///
/// This value object formats and validates codes. Number allocation belongs in
/// the repository transaction that persists the document.
enum BusinessDocumentKind { receipt, payment, stockIn, stockOut }

extension BusinessDocumentKindPrefix on BusinessDocumentKind {
  String get prefix => switch (this) {
    BusinessDocumentKind.receipt => 'THU',
    BusinessDocumentKind.payment => 'CHI',
    BusinessDocumentKind.stockIn => 'NHAP',
    BusinessDocumentKind.stockOut => 'XUAT',
  };
}

class BusinessReferenceCode {
  const BusinessReferenceCode._(this.kind, this.year, this.month, this.sequence);

  final BusinessDocumentKind kind;
  final int year;
  final int month;
  final int sequence;

  factory BusinessReferenceCode.forDate({
    required BusinessDocumentKind kind,
    required DateTime date,
    required int sequence,
  }) {
    if (date.year < 1 || date.year > 9999 || sequence < 1 || sequence > 999) {
      throw const FormatException('Document year or monthly sequence is out of range.');
    }
    return BusinessReferenceCode._(kind, date.year, date.month, sequence);
  }

  static BusinessReferenceCode parse(String value) {
    final match = RegExp(r'^(THU|CHI|NHAP|XUAT)-(\d{4})(0[1-9]|1[0-2])-(\d{3})$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid business reference code.');
    }
    final sequence = int.parse(match.group(4)!);
    if (sequence == 0) {
      throw const FormatException('Monthly sequence must start at 001.');
    }
    final kind = BusinessDocumentKind.values.singleWhere(
      (candidate) => candidate.prefix == match.group(1),
    );
    return BusinessReferenceCode._(
      kind,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      sequence,
    );
  }

  @override
  String toString() =>
      '${kind.prefix}-${year.toString().padLeft(4, '0')}${month.toString().padLeft(2, '0')}-${sequence.toString().padLeft(3, '0')}';
}
