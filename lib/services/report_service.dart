import 'dart:io';
import 'dart:html' as html; // Bắt buộc có dòng này để chạy trên Web
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';

class ReportService {
  // ============= BÁO CÁO TỒN KHO =============
  static Future<void> exportWarehouseReport(WarehouseProvider provider) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['BÁO CÁO TỒN KHO'];

      // Tiêu đề
      _addTitle(sheet, 'BÁO CÁO TỒN KHO');
      sheet.appendRow([]);

      // Header
      _addHeader(sheet, [
        'Mã hàng',
        'Tên hàng hóa',
        'Đơn vị tính',
        'Đơn giá nhập',
        'Nhà cung cấp',
        'Tồn kho',
      ]);

      // Dữ liệu
      for (var item in provider.items) {
        sheet.appendRow([
          TextCellValue(item.id),
          TextCellValue(item.name),
          TextCellValue(item.unit),
          DoubleCellValue(item.importPrice),
          TextCellValue(item.supplier),
          DoubleCellValue(item.stock.toDouble()),
        ]);
      }

      // Tổng cộng
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue('Tổng số mặt hàng:'),
        TextCellValue(provider.items.length.toString()),
      ]);

      // Định dạng độ rộng cột
      _applyFormatting(sheet);
      await _saveAndOpen(excel, 'BaoCaoTonKho.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo kho: $e');
      rethrow;
    }
  }

  // ============= BÁO CÁO MÁY MÓC =============
  static Future<void> exportMachineReport(MachineProvider provider) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['BÁO CÁO MÁY MÓC'];

      _addTitle(sheet, 'BÁO CÁO MÁY MÓC');
      sheet.appendRow([]);

      _addHeader(sheet, [
        'Mã máy',
        'Tên máy',
        'Loại máy',
        'Hãng SX',
        'Năm SX',
        'Trạng thái',
        'Tổng giờ',
        'Nhiên liệu (L/h)',
      ]);

      for (var machine in provider.machines) {
        sheet.appendRow([
          TextCellValue(machine.id),
          TextCellValue(machine.name),
          TextCellValue(machine.type),
          TextCellValue(machine.manufacturer),
          TextCellValue(machine.year.toString()),
          TextCellValue(machine.status),
          DoubleCellValue(machine.totalHours.toDouble()),
          DoubleCellValue(machine.fuelConsumption),
        ]);
      }

      // Thống kê
      sheet.appendRow([]);
      final totalMachines = provider.machines.length;
      final goodMachines = provider.machines
          .where((m) => m.status == 'Tốt')
          .length;
      final maintenanceMachines = provider.machines
          .where((m) => m.status == 'Đang bảo trì')
          .length;
      final brokenMachines = provider.machines
          .where((m) => m.status == 'Hỏng')
          .length;

      sheet.appendRow([TextCellValue('TỔNG HỢP:')]);
      sheet.appendRow([
        TextCellValue('Tổng số máy:'),
        DoubleCellValue(totalMachines.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Đang hoạt động tốt:'),
        DoubleCellValue(goodMachines.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Đang bảo trì:'),
        DoubleCellValue(maintenanceMachines.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Bị hỏng:'),
        DoubleCellValue(brokenMachines.toDouble()),
      ]);

      _applyFormatting(sheet);
      await _saveAndOpen(excel, 'BaoCaoMayMoc.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo máy móc: $e');
      rethrow;
    }
  }

  // ============= BÁO CÁO NHÂN SỰ =============
  static Future<void> exportEmployeeReport(EmployeeProvider provider) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['BÁO CÁO NHÂN SỰ'];

      _addTitle(sheet, 'BÁO CÁO NHÂN SỰ');
      sheet.appendRow([]);

      _addHeader(sheet, [
        'Mã NV',
        'Họ tên',
        'Vị trí',
        'Bộ phận',
        'Lương/ngày',
        'SĐT',
        'Trạng thái',
      ]);

      for (var emp in provider.employees) {
        sheet.appendRow([
          TextCellValue(emp.id),
          TextCellValue(emp.name),
          TextCellValue(emp.position),
          TextCellValue(emp.department),
          DoubleCellValue(emp.dailyRate),
          TextCellValue(emp.phone),
          TextCellValue(emp.isActive ? 'Đang làm' : 'Nghỉ'),
        ]);
      }

      // Thống kê
      sheet.appendRow([]);
      final total = provider.employees.length;
      final active = provider.employees.where((e) => e.isActive).length;
      final production = provider.getEmployeesByDepartment('Sản xuất').length;
      final office = provider.getEmployeesByDepartment('Văn phòng').length;

      sheet.appendRow([TextCellValue('TỔNG HỢP:')]);
      sheet.appendRow([
        TextCellValue('Tổng nhân viên:'),
        DoubleCellValue(total.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Đang làm:'),
        DoubleCellValue(active.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Bộ phận sản xuất:'),
        DoubleCellValue(production.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Bộ phận văn phòng:'),
        DoubleCellValue(office.toDouble()),
      ]);

      _applyFormatting(sheet);
      await _saveAndOpen(excel, 'BaoCaoNhanSu.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo nhân sự: $e');
      rethrow;
    }
  }

  // ============= BÁO CÁO TỔNG HỢP =============
  static Future<void> exportSummaryReport(
    WarehouseProvider warehouseProvider,
    MachineProvider machineProvider,
    EmployeeProvider employeeProvider,
  ) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['BÁO CÁO TỔNG HỢP'];

      _addTitle(sheet, 'BÁO CÁO TỔNG HỢP TRANG TRẠI');
      sheet.appendRow([]);

      // 1. Thống kê kho
      sheet.appendRow([TextCellValue('1. THỐNG KÊ KHO')]);
      sheet.appendRow([
        TextCellValue('Tổng số mặt hàng:'),
        DoubleCellValue(warehouseProvider.items.length.toDouble()),
      ]);

      int totalStock = 0;
      double totalValue = 0;
      for (var item in warehouseProvider.items) {
        totalStock += item.stock;
        totalValue += item.stock * item.importPrice;
      }
      sheet.appendRow([
        TextCellValue('Tổng số lượng tồn:'),
        DoubleCellValue(totalStock.toDouble()),
      ]);
      sheet.appendRow([
        TextCellValue('Tổng giá trị tồn kho:'),
        TextCellValue(totalValue.toStringAsFixed(0) + ' VND'),
      ]);
      sheet.appendRow([]);

      // 2. Thống kê máy móc
      sheet.appendRow([TextCellValue('2. THỐNG KÊ MÁY MÓC')]);
      sheet.appendRow([
        TextCellValue('Tổng số máy:'),
        DoubleCellValue(machineProvider.machines.length.toDouble()),
      ]);
      final goodMachines = machineProvider.machines
          .where((m) => m.status == 'Tốt')
          .length;
      sheet.appendRow([
        TextCellValue('Máy đang hoạt động tốt:'),
        DoubleCellValue(goodMachines.toDouble()),
      ]);

      int totalHours = 0;
      for (var machine in machineProvider.machines) {
        totalHours += machine.totalHours;
      }
      sheet.appendRow([
        TextCellValue('Tổng giờ vận hành:'),
        DoubleCellValue(totalHours.toDouble()),
      ]);
      sheet.appendRow([]);

      // 3. Thống kê nhân sự
      sheet.appendRow([TextCellValue('3. THỐNG KÊ NHÂN SỰ')]);
      sheet.appendRow([
        TextCellValue('Tổng nhân viên:'),
        DoubleCellValue(employeeProvider.employees.length.toDouble()),
      ]);
      final activeEmployees = employeeProvider.employees
          .where((e) => e.isActive)
          .length;
      sheet.appendRow([
        TextCellValue('Nhân viên đang làm:'),
        DoubleCellValue(activeEmployees.toDouble()),
      ]);
      sheet.appendRow([]);

      // 4. Tổng hợp nhanh
      sheet.appendRow([TextCellValue('4. TỔNG HỢP CHUNG')]);
      sheet.appendRow([
        TextCellValue('Ngày xuất báo cáo:'),
        TextCellValue(DateTime.now().toString().split(' ')[0]),
      ]);
      sheet.appendRow([]);

      _applyFormatting(sheet);
      await _saveAndOpen(excel, 'BaoCaoTongHop.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo tổng hợp: $e');
      rethrow;
    }
  }

  // ============= CÁC HÀM HỖ TRỢ =============

  // Thêm tiêu đề
  static void _addTitle(Sheet sheet, String title) {
    sheet.appendRow([TextCellValue(title)]);
  }

  // Thêm header (Đã gỡ bỏ phần tô màu phức tạp, chỉ để in đậm vì API thay đổi liên tục)
  static void _addHeader(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
  }

  // Định dạng độ rộng cột cơ bản
  static void _applyFormatting(Sheet sheet) {
    for (int i = 0; i < 10; i++) {
      sheet.setColumnWidth(i, 20);
    }
  }

  // Lưu file và mở (Đã sửa để chạy được trên cả ANDROID/IOS và WEB)
  static Future<void> _saveAndOpen(Excel excel, String fileName) async {
    final fileBytes = excel.save();
    if (fileBytes == null) {
      throw Exception('Không thể tạo file Excel');
    }

    // Kiểm tra nếu đang chạy trên điện thoại (Mobile)
    if (Platform.isAndroid || Platform.isIOS) {
      final directory = await getExternalStorageDirectory();
      final downloadsPath =
          directory?.path ?? (await getApplicationDocumentsDirectory()).path;
      final filePath = '$downloadsPath/$fileName';
      final file = File(filePath);

      await file.writeAsBytes(fileBytes);
      print('File đã được lưu tại: $filePath');

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        print('Không thể mở file: ${result.message}');
      }
    } else {
      // Nếu đang chạy trên trình duyệt (Web), dùng cách tạo link tải xuống
      final blob = html.Blob([
        fileBytes,
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..target = 'blank'
        ..download = fileName;

      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);

      print('Đang tải file xuống trình duyệt: $fileName');
    }
  }
}
