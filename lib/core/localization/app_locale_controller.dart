import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

class AppLocaleController extends ChangeNotifier {
  AppLocaleController({Locale initialLocale = const Locale('vi')})
    : _locale = _normalize(initialLocale);

  Locale _locale;

  Locale get locale => _locale;

  bool setLocale(Locale locale) {
    final normalized = _normalize(locale);
    if (!_isSupported(locale) || normalized == _locale) {
      return false;
    }
    _locale = normalized;
    notifyListeners();
    return true;
  }

  static bool _isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  static Locale _normalize(Locale locale) {
    return AppLocalizations.supportedLocales.firstWhere(
      (supported) => supported.languageCode == locale.languageCode,
      orElse: () => const Locale('vi'),
    );
  }
}
