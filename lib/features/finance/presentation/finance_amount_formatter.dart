import 'package:flutter/services.dart';

/// Groups integer amounts for display without changing the stored value.
class FinanceAmountFormatter extends TextInputFormatter {
  static String groupExact(String text) {
    final parts = text.split('.');
    return parts.length == 1
        ? group(parts.first)
        : '${group(parts.first)},${parts[1]}';
  }

  static String digits(String text) => text.replaceAll('.', '');

  static String group(String value) => value.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!RegExp(r'^[0-9.]*$').hasMatch(newValue.text)) {
      return oldValue;
    }
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final formatted = group(digits(newValue.text));
    int position(int offset) {
      if (offset < 0) {
        return formatted.length;
      }
      final end = offset > newValue.text.length ? newValue.text.length : offset;
      final count = digits(newValue.text.substring(0, end)).length;
      if (count == 0) {
        return 0;
      }
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != '.') {
          seen++;
          if (seen == count) {
            return i + 1;
          }
        }
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: position(newValue.selection.baseOffset),
        extentOffset: position(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
    );
  }
}
