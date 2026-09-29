import 'package:agrico_deepseek/core/localization/app_locale_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to Vietnamese and switches to a supported locale', () {
    final controller = AppLocaleController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.locale, const Locale('vi'));
    expect(controller.setLocale(const Locale('lo', 'LA')), isTrue);
    expect(controller.locale, const Locale('lo'));
    expect(notifications, 1);
  });

  test('rejects unsupported and unchanged locales', () {
    final controller = AppLocaleController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.setLocale(const Locale('fr')), isFalse);
    expect(controller.setLocale(const Locale('vi', 'VN')), isFalse);
    expect(controller.locale, const Locale('vi'));
    expect(notifications, 0);
  });
}
