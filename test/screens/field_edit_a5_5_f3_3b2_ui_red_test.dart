import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// F3.3-B2 UI contract RED tests. Static source assertions deliberately avoid
// constructing the production singleton (which can open a real SQLite DB).
void main() {
  late String source;
  setUpAll(() {
    source = File('lib/screens/field_edit_screen.dart').readAsStringSync();
  });

  test('B2 UI RED: save awaits confirmed local SQLite persistence', () {
    expect(source, contains('await _provider.saveFieldLocally('),
        reason: 'Do not report success or pop before local save completes.');
  });

  test('B2 UI RED: saving state prevents duplicate submissions', () {
    expect(source, contains('bool _isSaving = false;'));
    expect(source, contains('onPressed: _isSaving ? null : _save'));
  });

  test('B2 UI RED: save failure is caught and shown without success pop', () {
    expect(source, contains('catch ('),
        reason: 'SQLite errors must be handled in the edit screen.');
    expect(source, contains('ScaffoldMessenger.of(context).showSnackBar('),
        reason: 'Keep the screen open and explain the local save failure.');
  });
}