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
      'error.permissionDenied': 'Bạn không có quyền thực hiện thao tác này.',
      'landParcel.create.success': 'Đã tạo lô đất.',
      'landParcel.update.success': 'Đã cập nhật thông tin lô đất.',
      'landParcel.error.notFound': 'Không tìm thấy lô đất.',
      'landParcel.geometry.invalid': 'Ranh giới lô đất không hợp lệ.',
      'landParcel.persistence.failed': 'Không thể lưu thay đổi lô đất.',
      'landParcel.boundary.verifiedConfirmation':
          'Ranh giới đã được xác minh. Hãy xác nhận trước khi thay thế.',
      'landParcel.boundary.replaceSuccess': 'Đã cập nhật ranh giới lô đất.',
      'landParcel.boundary.verifySuccess': 'Đã cập nhật trạng thái xác minh.',
      'landParcel.gps.invalidSource': 'Nguồn đo GPS không hợp lệ.',
      'landParcel.import.previewReady':
          'Đã chuẩn bị bản xem trước nhập dữ liệu.',
      'landParcel.import.failed': 'Không thể đọc tệp KML/KMZ.',
      'landParcel.export.success': 'Đã xuất tệp KML/KMZ.',
      'landParcel.export.failed': 'Không thể xuất tệp KML/KMZ.',
      'landParcel.preview.warning': 'Hãy kiểm tra cảnh báo trước khi xác nhận.',
      'survey.household': 'Hộ gia đình',
      'survey.administrativeLocation': 'Địa chỉ hành chính',
      'survey.landUse': 'Mục đích sử dụng đất',
      'survey.landCondition': 'Hiện trạng đất',
      'survey.clearingStatus': 'Tình trạng phát quang',
      'survey.readinessStatus': 'Mức độ sẵn sàng',
      'survey.crop': 'Cây trồng',
      'survey.cropCondition': 'Tình trạng cây trồng',
      'survey.quantityUnit': 'Số lượng và đơn vị',
      'survey.record': 'Khảo sát đất',
      'survey.surveyor': 'Người khảo sát',
      'survey.attachment': 'Tệp đính kèm',
      'survey.validation.invalid': 'Dữ liệu khảo sát không hợp lệ.',
      'survey.persistence.failed': 'Không thể lưu dữ liệu khảo sát.',
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
      'error.permissionDenied': 'ທ່ານບໍ່ມີສິດເຮັດລາຍການນີ້.',
      'landParcel.create.success': 'ສ້າງແປງດິນແລ້ວ.',
      'landParcel.update.success': 'ອັບເດດຂໍ້ມູນແປງດິນແລ້ວ.',
      'landParcel.error.notFound': 'ບໍ່ພົບແປງດິນ.',
      'landParcel.geometry.invalid': 'ເຂດແດນແປງດິນບໍ່ຖືກຕ້ອງ.',
      'landParcel.persistence.failed': 'ບໍ່ສາມາດບັນທຶກການປ່ຽນແປງໄດ້.',
      'landParcel.boundary.verifiedConfirmation':
          'ເຂດແດນນີ້ຖືກຢືນຢັນແລ້ວ. ກະລຸນາຢືນຢັນກ່ອນປ່ຽນແທນ.',
      'landParcel.boundary.replaceSuccess': 'ອັບເດດເຂດແດນແລ້ວ.',
      'landParcel.boundary.verifySuccess': 'ອັບເດດສະຖານະການຢືນຢັນແລ້ວ.',
      'landParcel.gps.invalidSource': 'ແຫຼ່ງຂໍ້ມູນ GPS ບໍ່ຖືກຕ້ອງ.',
      'landParcel.import.previewReady': 'ກຽມຕົວຢ່າງກ່ອນນຳເຂົ້າແລ້ວ.',
      'landParcel.import.failed': 'ບໍ່ສາມາດອ່ານໄຟລ໌ KML/KMZ.',
      'landParcel.export.success': 'ສົ່ງອອກໄຟລ໌ KML/KMZ ແລ້ວ.',
      'landParcel.export.failed': 'ບໍ່ສາມາດສົ່ງອອກ KML/KMZ.',
      'landParcel.preview.warning': 'ກະລຸນາກວດຄຳເຕືອນກ່ອນຢືນຢັນ.',
      'survey.household': 'ຄົວເຮືອນ',
      'survey.administrativeLocation': 'ທີ່ຢູ່ປົກຄອງ',
      'survey.landUse': 'ການນຳໃຊ້ທີ່ດິນ',
      'survey.landCondition': 'ສະພາບທີ່ດິນ',
      'survey.clearingStatus': 'ສະຖານະການຖາງ',
      'survey.readinessStatus': 'ຄວາມພ້ອມ',
      'survey.crop': 'ພືດປູກ',
      'survey.cropCondition': 'ສະພາບພືດ',
      'survey.quantityUnit': 'ຈຳນວນ ແລະ ຫົວໜ່ວຍ',
      'survey.record': 'ການສຳຫຼວດທີ່ດິນ',
      'survey.surveyor': 'ຜູ້ສຳຫຼວດ',
      'survey.attachment': 'ໄຟລ໌ແນບ',
      'survey.validation.invalid': 'ຂໍ້ມູນສຳຫຼວດບໍ່ຖືກຕ້ອງ.',
      'survey.persistence.failed': 'ບໍ່ສາມາດບັນທຶກຂໍ້ມູນສຳຫຼວດ.',
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
      'error.permissionDenied': 'You do not have permission for this action.',
      'landParcel.create.success': 'Land parcel created.',
      'landParcel.update.success': 'Land parcel details updated.',
      'landParcel.error.notFound': 'Land parcel not found.',
      'landParcel.geometry.invalid': 'The land parcel boundary is invalid.',
      'landParcel.persistence.failed':
          'The land parcel change could not be saved.',
      'landParcel.boundary.verifiedConfirmation':
          'This boundary is verified. Confirm before replacing it.',
      'landParcel.boundary.replaceSuccess': 'Land parcel boundary updated.',
      'landParcel.boundary.verifySuccess': 'Verification status updated.',
      'landParcel.gps.invalidSource': 'The GPS measurement source is invalid.',
      'landParcel.import.previewReady': 'Import preview is ready.',
      'landParcel.import.failed': 'The KML/KMZ file could not be read.',
      'landParcel.export.success': 'KML/KMZ export is ready.',
      'landParcel.export.failed': 'The KML/KMZ file could not be exported.',
      'landParcel.preview.warning': 'Review warnings before confirming.',
      'survey.household': 'Household',
      'survey.administrativeLocation': 'Administrative location',
      'survey.landUse': 'Land use',
      'survey.landCondition': 'Land condition',
      'survey.clearingStatus': 'Clearing status',
      'survey.readinessStatus': 'Readiness status',
      'survey.crop': 'Crop',
      'survey.cropCondition': 'Crop condition',
      'survey.quantityUnit': 'Quantity and unit',
      'survey.record': 'Land survey',
      'survey.surveyor': 'Surveyor',
      'survey.attachment': 'Attachment',
      'survey.validation.invalid': 'The survey data is invalid.',
      'survey.persistence.failed': 'The survey data could not be saved.',
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
