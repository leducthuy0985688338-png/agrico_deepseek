import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vi, lo and en catalogues have identical keys', () {
    final expected = AppLocalizations.keysFor(const Locale('vi'));

    expect(expected, isNotEmpty);
    expect(AppLocalizations.keysFor(const Locale('lo')), expected);
    expect(AppLocalizations.keysFor(const Locale('en')), expected);
  });

  test('unsupported locale falls back to Vietnamese', () {
    expect(
      const AppLocalizations(Locale('fr')).text('auth.signIn'),
      'ĐĂNG NHẬP',
    );
  });

  test('missing key remains visible for diagnostics', () {
    expect(
      const AppLocalizations(Locale('vi')).text('missing.key'),
      'missing.key',
    );
  });
}
