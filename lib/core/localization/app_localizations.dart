import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Lightweight localization facade used while legacy screens are migrated.
///
/// Keeping the catalogue in Dart makes the v2 foundation immediately usable
/// without coupling domain code to Flutter's generated localization classes.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('vi'),
    Locale('lo'),
    Locale('en'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(value != null, 'AppLocalizations is not registered in MaterialApp.');
    return value!;
  }

  static const Map<String, Map<String, String>> _catalogue = {
    'vi': {
      'app.name': 'AGRICO ERP',
      'app.tagline': 'Quản lý nông nghiệp thông minh',
      'auth.username': 'Email / Tên đăng nhập',
      'auth.password': 'Mật khẩu',
      'auth.forgotPassword': 'Quên mật khẩu?',
      'auth.signIn': 'ĐĂNG NHẬP',
      'auth.demoHint': '💡 (Nhấn nút để vào Demo, không cần mật khẩu)',
      'common.loading': 'Đang tải…',
      'common.retry': 'Thử lại',
      'common.cancel': 'Hủy',
      'common.save': 'Lưu',
      'error.unauthorized': 'Bạn không có quyền thực hiện thao tác này.',
    },
    'lo': {
      'app.name': 'AGRICO ERP',
      'app.tagline': 'ການຈັດການກະສິກຳອັດສະລິຍະ',
      'auth.username': 'ອີເມວ / ຊື່ຜູ້ໃຊ້',
      'auth.password': 'ລະຫັດຜ່ານ',
      'auth.forgotPassword': 'ລືມລະຫັດຜ່ານ?',
      'auth.signIn': 'ເຂົ້າລະບົບ',
      'auth.demoHint': '💡 (ກົດປຸ່ມເພື່ອເຂົ້າ Demo ໂດຍບໍ່ຕ້ອງໃສ່ລະຫັດ)',
      'common.loading': 'ກຳລັງໂຫຼດ…',
      'common.retry': 'ລອງໃໝ່',
      'common.cancel': 'ຍົກເລີກ',
      'common.save': 'ບັນທຶກ',
      'error.unauthorized': 'ທ່ານບໍ່ມີສິດເຮັດລາຍການນີ້.',
    },
    'en': {
      'app.name': 'AGRICO ERP',
      'app.tagline': 'Smart agriculture management',
      'auth.username': 'Email / Username',
      'auth.password': 'Password',
      'auth.forgotPassword': 'Forgot password?',
      'auth.signIn': 'SIGN IN',
      'auth.demoHint': '💡 (Tap to enter the demo without a password)',
      'common.loading': 'Loading…',
      'common.retry': 'Retry',
      'common.cancel': 'Cancel',
      'common.save': 'Save',
      'error.unauthorized': 'You do not have permission for this action.',
    },
  };

  String text(String key) {
    final languageCode = _catalogue.containsKey(locale.languageCode)
        ? locale.languageCode
        : 'vi';
    return _catalogue[languageCode]?[key] ?? _catalogue['vi']?[key] ?? key;
  }

  @visibleForTesting
  static Set<String> keysFor(Locale locale) =>
      _catalogue[locale.languageCode]?.keys.toSet() ?? const {};
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
