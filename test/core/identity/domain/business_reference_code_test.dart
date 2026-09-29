import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';

void main() {
  test('type, year, month and three-digit sequence remain distinct', () {
    final date = DateTime(2026, 9, 25);
    for (final kind in BusinessDocumentKind.values) {
      final code = BusinessReferenceCode.forDate(kind: kind, date: date, sequence: 1);
      expect(code.toString(), '${kind.prefix}-202609-001');
      expect(BusinessReferenceCode.parse(code.toString()).kind, kind);
    }
    expect(BusinessReferenceCode.forDate(
      kind: BusinessDocumentKind.receipt,
      date: DateTime(2026, 10),
      sequence: 1,
    ).toString(), 'THU-202610-001');
  });

  test('invalid codes and exhausted three-digit sequence are rejected', () {
    for (final code in ['THU-202600-001', 'THU-202613-001', 'THU-202609-000', 'CHI-202609-1000', 'THU-202609-1']) {
      expect(() => BusinessReferenceCode.parse(code), throwsFormatException);
    }
    expect(() => BusinessReferenceCode.forDate(
      kind: BusinessDocumentKind.stockIn,
      date: DateTime(2026, 9),
      sequence: 1000,
    ), throwsFormatException);
  });
}
