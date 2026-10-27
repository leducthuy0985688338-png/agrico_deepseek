import 'package:flutter/widgets.dart';

class WorkspaceStrings {
  WorkspaceStrings(BuildContext context)
    : language = Localizations.localeOf(context).languageCode;
  final String language;
  int get index => language == 'lo'
      ? 2
      : language == 'en'
      ? 1
      : 0;
  String tr(String vi, String en, String lo) => [vi, en, lo][index];
  String name(dynamic names) =>
      names is List ? names[index] as String : names.toString();
  String state(String value) =>
      ({
        'draft': ['Nháp', 'Draft', 'ຮ່າງ'],
        'assigned': ['Đã giao', 'Assigned', 'ມອບແລ້ວ'],
        'accepted': ['Đã nhận', 'Accepted', 'ຮັບແລ້ວ'],
        'inProgress': ['Đang làm', 'In progress', 'ກຳລັງເຮັດ'],
        'submitted': ['Đã gửi', 'Submitted', 'ສົ່ງແລ້ວ'],
        'received': ['Đã tiếp nhận', 'Received', 'ຮັບແລ້ວ'],
        'approved': ['Đã duyệt', 'Approved', 'ອະນຸມັດແລ້ວ'],
        'completed': ['Hoàn tất', 'Completed', 'ສຳເລັດ'],
        'verified': ['Đã nghiệm thu', 'Verified', 'ກວດຮັບແລ້ວ'],
        'rework': ['Yêu cầu làm lại', 'Rework', 'ໃຫ້ເຮັດໃໝ່'],
        'needsChanges': ['Cần bổ sung', 'Needs changes', 'ຕ້ອງເພີ່ມເຕີມ'],
        'rejected': ['Từ chối', 'Rejected', 'ປະຕິເສດ'],
        'withdrawn': ['Đã rút', 'Withdrawn', 'ຖອນແລ້ວ'],
        'cancelled': ['Đã hủy', 'Cancelled', 'ຍົກເລີກ'],
        'open': ['Đang mở', 'Open', 'ເປີດ'],
        'sent': ['Đã gửi', 'Sent', 'ສົ່ງແລ້ວ'],
      }[value] ??
      [value, value, value])[index];
  String error(Object e) {
    final v = e.toString();
    if (v.contains('pending')) {
      return tr(
        'Chưa nhận xác nhận máy chủ. Lệnh vẫn ở hàng chờ; kết nối lại để kiểm tra.',
        'Server confirmation pending. Reconnect to retry the same operation.',
        'ລໍຖ້າເຊີບເວີ. ເຊື່ອມຕໍ່ໃໝ່ເພື່ອກວດສອບ.',
      );
    }
    if (v.contains('conflict')) {
      return tr(
        'Dữ liệu đã đổi. Tải lại trước khi thao tác.',
        'Data changed. Reload before acting.',
        'ຂໍ້ມູນປ່ຽນແລ້ວ. ໂຫຼດໃໝ່.',
      );
    }
    if (v.contains('denied') ||
        v.contains('permission-denied') ||
        v.contains('Session')) {
      return tr(
        'Không có quyền hoặc phiên quyền đã thay đổi.',
        'Access denied or session changed.',
        'ບໍ່ມີສິດ ຫຼື ສິດປ່ຽນແລ້ວ.',
      );
    }
    return tr(
      'Không thực hiện được. Kiểm tra dữ liệu, quyền, kết nối và cấu hình máy chủ.',
      'Unable to complete. Check input, access, connection and server setup.',
      'ບໍ່ສາມາດດຳເນີນການ. ກວດຂໍ້ມູນ ສິດ ແລະ ການເຊື່ອມຕໍ່.',
    );
  }
}
