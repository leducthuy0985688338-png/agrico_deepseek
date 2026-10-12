import 'package:agrico_deepseek/features/finance/presentation/finance_amount_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = FinanceAmountFormatter();
  TextEditingValue value(String text, [int? cursor]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );
  test('typing and pasting group thousands', () {
    for (final entry in {
      '1': '1',
      '1000': '1.000',
      '1000000': '1.000.000',
      '1.000.000': '1.000.000',
    }.entries) {
      final result = formatter.formatEditUpdate(value(''), value(entry.key));
      expect(result.text, entry.value);
      expect(result.selection.baseOffset, entry.value.length);
      expect(
        int.tryParse(FinanceAmountFormatter.digits(result.text)),
        int.parse(entry.key.replaceAll('.', '')),
      );
    }
  });
  test('deleting digits and clearing the field are supported', () {
    expect(
      formatter.formatEditUpdate(value('1.000'), value('1.00')).text,
      '100',
    );
    expect(formatter.formatEditUpdate(value('1.000'), value('')).text, '');
  });
  test('editing within an amount preserves cursor by digit position', () {
    final result = formatter.formatEditUpdate(
      value('1.000.000'),
      value('12.000.000', 2),
    );
    expect(result.text, '12.000.000');
    expect(result.selection.baseOffset, 2);
  });
  test('negative, decimal comma and alphabetic input are rejected', () {
    for (final text in ['-1000', '1,25', 'abc']) {
      final old = value('1.000');
      expect(formatter.formatEditUpdate(old, value(text)), old);
    }
  });
}
