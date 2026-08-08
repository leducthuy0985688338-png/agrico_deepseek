import 'package:excel/excel.dart';

import '../models/finance_model.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';

import 'report_file_saver.dart';

class ReportService {
  // ============================================================
  // BÁO CÁO KHO
  // ============================================================

  static Future<void> exportWarehouseReport(WarehouseProvider provider) async {
    try {
      final excel = Excel.createExcel();

      final sheet = excel['BÁO CÁO TỒN KHO'];

      _addTitle(sheet, 'BÁO CÁO TỒN KHO');

      _addEmptyRow(sheet);

      _addHeader(sheet, [
        'Mã hàng',
        'Tên hàng hóa',
        'Đơn vị tính',
        'Đơn giá nhập',
        'Nhà cung cấp',
        'Tồn kho',
        'Giá trị tồn',
      ]);

      for (final item in provider.items) {
        final stock = _toDouble(item.stock);

        final importPrice = _toDouble(item.importPrice);

        sheet.appendRow([
          TextCellValue(item.id),
          TextCellValue(item.name),
          TextCellValue(item.unit),
          DoubleCellValue(importPrice),
          TextCellValue(item.supplier),
          DoubleCellValue(stock),
          DoubleCellValue(stock * importPrice),
        ]);
      }

      _addEmptyRow(sheet);

      final totalValue = provider.items.fold<double>(
        0,
        (sum, item) =>
            sum + _toDouble(item.stock) * _toDouble(item.importPrice),
      );

      sheet.appendRow([
        TextCellValue('Tổng số mặt hàng:'),
        IntCellValue(provider.items.length),
      ]);

      sheet.appendRow([
        TextCellValue('Tổng giá trị tồn kho:'),
        DoubleCellValue(totalValue),
      ]);

      _applyFormatting(sheet);

      await saveExcelFile(excel, 'BaoCaoTonKho.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo kho: $e');
      rethrow;
    }
  }

  // ============================================================
  // BÁO CÁO MÁY MÓC
  // ============================================================

  static Future<void> exportMachineReport(MachineProvider provider) async {
    try {
      final excel = Excel.createExcel();

      final sheet = excel['BÁO CÁO MÁY MÓC'];

      _addTitle(sheet, 'BÁO CÁO MÁY MÓC');

      _addEmptyRow(sheet);

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

      for (final machine in provider.machines) {
        sheet.appendRow([
          TextCellValue(machine.id),
          TextCellValue(machine.name),
          TextCellValue(machine.type),
          TextCellValue(machine.manufacturer),
          IntCellValue(_toInt(machine.year)),
          TextCellValue(machine.status),
          DoubleCellValue(_toDouble(machine.totalHours)),
          DoubleCellValue(_toDouble(machine.fuelConsumption)),
        ]);
      }

      _addEmptyRow(sheet);

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
        IntCellValue(totalMachines),
      ]);

      sheet.appendRow([
        TextCellValue('Đang hoạt động tốt:'),
        IntCellValue(goodMachines),
      ]);

      sheet.appendRow([
        TextCellValue('Đang bảo trì:'),
        IntCellValue(maintenanceMachines),
      ]);

      sheet.appendRow([
        TextCellValue('Bị hỏng:'),
        IntCellValue(brokenMachines),
      ]);

      _applyFormatting(sheet);

      await saveExcelFile(excel, 'BaoCaoMayMoc.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo máy móc: $e');
      rethrow;
    }
  }

  // ============================================================
  // BÁO CÁO NHÂN SỰ
  // ============================================================

  static Future<void> exportEmployeeReport(EmployeeProvider provider) async {
    try {
      final excel = Excel.createExcel();

      final sheet = excel['BÁO CÁO NHÂN SỰ'];

      _addTitle(sheet, 'BÁO CÁO NHÂN SỰ');

      _addEmptyRow(sheet);

      _addHeader(sheet, [
        'Mã NV',
        'Họ tên',
        'Vị trí',
        'Bộ phận',
        'Lương/ngày',
        'SĐT',
        'Trạng thái',
      ]);

      for (final emp in provider.employees) {
        sheet.appendRow([
          TextCellValue(emp.id),
          TextCellValue(emp.name),
          TextCellValue(emp.position),
          TextCellValue(emp.department),
          DoubleCellValue(_toDouble(emp.dailyRate)),
          TextCellValue(emp.phone),
          TextCellValue(emp.isActive ? 'Đang làm' : 'Nghỉ'),
        ]);
      }

      _addEmptyRow(sheet);

      final total = provider.employees.length;

      final active = provider.employees.where((e) => e.isActive).length;

      final production = provider.getEmployeesByDepartment('Sản xuất').length;

      final office = provider.getEmployeesByDepartment('Văn phòng').length;

      sheet.appendRow([TextCellValue('TỔNG HỢP:')]);

      sheet.appendRow([TextCellValue('Tổng nhân viên:'), IntCellValue(total)]);

      sheet.appendRow([TextCellValue('Đang làm:'), IntCellValue(active)]);

      sheet.appendRow([
        TextCellValue('Bộ phận sản xuất:'),
        IntCellValue(production),
      ]);

      sheet.appendRow([
        TextCellValue('Bộ phận văn phòng:'),
        IntCellValue(office),
      ]);

      _applyFormatting(sheet);

      await saveExcelFile(excel, 'BaoCaoNhanSu.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo nhân sự: $e');
      rethrow;
    }
  }

  // ============================================================
  // BÁO CÁO TÀI CHÍNH TỔNG HỢP
  // ============================================================

  static Future<void> exportFinanceReport(FinanceProvider provider) async {
    try {
      final excel = Excel.createExcel();

      // ----------------------------------------------------------
      // SHEET 1: TỔNG QUAN
      // ----------------------------------------------------------

      final sheet1 = excel['TỔNG QUAN'];

      _addTitle(sheet1, 'BÁO CÁO TÀI CHÍNH TỔNG HỢP');

      _addEmptyRow(sheet1);

      final totalRevenue = _toDouble(provider.getTotalRevenue());

      final totalCost = _toDouble(provider.getTotalCost());

      final totalProfit = _toDouble(provider.getTotalProfit());

      sheet1.appendRow([TextCellValue('TỔNG QUAN TÀI CHÍNH')]);

      sheet1.appendRow([
        TextCellValue('Tổng thu:'),
        DoubleCellValue(totalRevenue),
      ]);

      sheet1.appendRow([
        TextCellValue('Tổng chi:'),
        DoubleCellValue(totalCost),
      ]);

      sheet1.appendRow([
        TextCellValue('Lợi nhuận:'),
        DoubleCellValue(totalProfit),
      ]);

      final profitMargin = totalRevenue > 0
          ? totalProfit / totalRevenue * 100
          : 0.0;

      sheet1.appendRow([
        TextCellValue('Tỷ suất lợi nhuận:'),
        DoubleCellValue(profitMargin),
      ]);

      _addEmptyRow(sheet1);

      sheet1.appendRow([
        TextCellValue('Ngày xuất báo cáo:'),
        TextCellValue(_formatDateTime(DateTime.now())),
      ]);

      _applyFormatting(sheet1);

      // ----------------------------------------------------------
      // SHEET 2: THU CHI THEO LÔ
      // ----------------------------------------------------------

      final sheet2 = excel['THU CHI THEO LÔ'];

      _addTitle(sheet2, 'BÁO CÁO THU CHI THEO LÔ');

      _addEmptyRow(sheet2);

      final reports = provider.generateProfitReport();

      _addHeader(sheet2, [
        'Mã lô',
        'Tên lô',
        'Tổng thu (VND)',
        'Tổng chi (VND)',
        'Lợi nhuận (VND)',
        'Tỷ suất (%)',
      ]);

      for (final report in reports) {
        sheet2.appendRow([
          TextCellValue(report.fieldId),
          TextCellValue(report.fieldName),
          DoubleCellValue(_toDouble(report.totalRevenue)),
          DoubleCellValue(_toDouble(report.totalCost)),
          DoubleCellValue(_toDouble(report.profit)),
          DoubleCellValue(_toDouble(report.profitMargin)),
        ]);
      }

      _addEmptyRow(sheet2);

      sheet2.appendRow([
        TextCellValue('TỔNG CỘNG:'),
        TextCellValue(''),
        DoubleCellValue(totalRevenue),
        DoubleCellValue(totalCost),
        DoubleCellValue(totalProfit),
        DoubleCellValue(profitMargin),
      ]);

      _applyFormatting(sheet2);

      // ----------------------------------------------------------
      // SHEET 3: CHI TIẾT GIAO DỊCH
      // ----------------------------------------------------------

      final sheet3 = excel['CHI TIẾT GIAO DỊCH'];

      _addTitle(sheet3, 'CHI TIẾT GIAO DỊCH TÀI CHÍNH');

      _addEmptyRow(sheet3);

      _addHeader(sheet3, [
        'Mã GD',
        'Ngày',
        'Lô đất',
        'Loại',
        'Danh mục',
        'Số tiền (VND)',
        'Mô tả',
        'Máy liên quan',
      ]);

      for (final record in provider.records) {
        sheet3.appendRow([
          TextCellValue(record.id),
          TextCellValue(_formatDate(record.date)),
          TextCellValue(record.fieldName),
          TextCellValue(_transactionTypeName(record.type)),
          TextCellValue(record.category),
          DoubleCellValue(_toDouble(record.amount)),
          TextCellValue(record.description ?? ''),
          TextCellValue(record.machineName ?? ''),
        ]);
      }

      _applyFormatting(sheet3);

      // ----------------------------------------------------------
      // SHEET 4: PHÂN BỔ CHI PHÍ
      // ----------------------------------------------------------

      final sheet4 = excel['PHÂN BỔ CHI PHÍ'];

      _addTitle(sheet4, 'PHÂN BỔ CHI PHÍ THEO DANH MỤC');

      _addEmptyRow(sheet4);

      final costByCategory = provider.getCostByCategory();

      _addHeader(sheet4, ['Danh mục', 'Số tiền (VND)', 'Tỷ lệ (%)']);

      double totalCostAll = 0;

      for (final value in costByCategory.values) {
        totalCostAll += _toDouble(value);
      }

      for (final entry in costByCategory.entries) {
        final value = _toDouble(entry.value);

        final percentage = totalCostAll > 0 ? value / totalCostAll * 100 : 0.0;

        sheet4.appendRow([
          TextCellValue(entry.key),
          DoubleCellValue(value),
          DoubleCellValue(percentage),
        ]);
      }

      _addEmptyRow(sheet4);

      sheet4.appendRow([
        TextCellValue('TỔNG CỘNG:'),
        DoubleCellValue(totalCostAll),
        DoubleCellValue(100),
      ]);

      _applyFormatting(sheet4);

      await saveExcelFile(excel, 'BaoCaoTaiChinh.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo tài chính: $e');
      rethrow;
    }
  }

  // ============================================================
  // BÁO CÁO TÀI CHÍNH THEO LÔ
  // ============================================================

  static Future<void> exportFinanceByFieldReport(
    FinanceProvider provider,
    String fieldId,
    String fieldName,
  ) async {
    try {
      final excel = Excel.createExcel();

      final sheet1 = excel['TỔNG QUAN LÔ'];

      _addTitle(sheet1, 'BÁO CÁO TÀI CHÍNH - $fieldName');

      _addEmptyRow(sheet1);

      final totalRevenue = _toDouble(provider.getTotalRevenueByField(fieldId));

      final totalCost = _toDouble(provider.getTotalCostByField(fieldId));

      final profit = totalRevenue - totalCost;

      final margin = totalRevenue > 0 ? profit / totalRevenue * 100 : 0.0;

      sheet1.appendRow([TextCellValue('THÔNG TIN LÔ')]);

      sheet1.appendRow([TextCellValue('Mã lô:'), TextCellValue(fieldId)]);

      sheet1.appendRow([TextCellValue('Tên lô:'), TextCellValue(fieldName)]);

      sheet1.appendRow([
        TextCellValue('Tổng thu:'),
        DoubleCellValue(totalRevenue),
      ]);

      sheet1.appendRow([
        TextCellValue('Tổng chi:'),
        DoubleCellValue(totalCost),
      ]);

      sheet1.appendRow([TextCellValue('Lợi nhuận:'), DoubleCellValue(profit)]);

      sheet1.appendRow([
        TextCellValue('Tỷ suất (%):'),
        DoubleCellValue(margin),
      ]);

      _addEmptyRow(sheet1);

      sheet1.appendRow([
        TextCellValue('Ngày xuất:'),
        TextCellValue(_formatDateTime(DateTime.now())),
      ]);

      _applyFormatting(sheet1);

      // ----------------------------------------------------------
      // SHEET 2
      // ----------------------------------------------------------

      final sheet2 = excel['CHI TIẾT GIAO DỊCH'];

      _addTitle(sheet2, 'CHI TIẾT GIAO DỊCH - $fieldName');

      _addEmptyRow(sheet2);

      final transactions = provider.getTransactionsByField(fieldId);

      _addHeader(sheet2, [
        'Ngày',
        'Loại',
        'Danh mục',
        'Số tiền (VND)',
        'Mô tả',
        'Máy liên quan',
      ]);

      for (final record in transactions) {
        sheet2.appendRow([
          TextCellValue(_formatDate(record.date)),
          TextCellValue(_transactionTypeName(record.type)),
          TextCellValue(record.category),
          DoubleCellValue(_toDouble(record.amount)),
          TextCellValue(record.description ?? ''),
          TextCellValue(record.machineName ?? ''),
        ]);
      }

      _addEmptyRow(sheet2);

      sheet2.appendRow([
        TextCellValue('TỔNG THU:'),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(totalRevenue),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      sheet2.appendRow([
        TextCellValue('TỔNG CHI:'),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(totalCost),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      sheet2.appendRow([
        TextCellValue('LỢI NHUẬN:'),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(profit),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      _applyFormatting(sheet2);

      await saveExcelFile(excel, 'BaoCaoTaiChinh_$fieldId.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo tài chính theo lô: $e');
      rethrow;
    }
  }

  // ============================================================
  // BÁO CÁO TỔNG HỢP HỆ THỐNG
  // ============================================================

  static Future<void> exportFullSystemReport(
    WarehouseProvider warehouseProvider,
    MachineProvider machineProvider,
    EmployeeProvider employeeProvider,
    FinanceProvider financeProvider,
    FuelProvider fuelProvider,
  ) async {
    try {
      final excel = Excel.createExcel();

      // ----------------------------------------------------------
      // SHEET 1: TỔNG QUAN
      // ----------------------------------------------------------

      final sheet1 = excel['TỔNG QUAN'];

      _addTitle(sheet1, 'BÁO CÁO TỔNG HỢP HỆ THỐNG');

      _addEmptyRow(sheet1);

      sheet1.appendRow([
        TextCellValue('Ngày xuất:'),
        TextCellValue(_formatDateTime(DateTime.now())),
      ]);

      _addEmptyRow(sheet1);

      // KHO

      sheet1.appendRow([TextCellValue('1. THỐNG KÊ KHO')]);

      sheet1.appendRow([
        TextCellValue('Số loại hàng:'),
        IntCellValue(warehouseProvider.items.length),
      ]);

      double totalStockValue = 0;

      for (final item in warehouseProvider.items) {
        totalStockValue += _toDouble(item.stock) * _toDouble(item.importPrice);
      }

      sheet1.appendRow([
        TextCellValue('Tổng giá trị tồn kho:'),
        DoubleCellValue(totalStockValue),
      ]);

      _addEmptyRow(sheet1);

      // MÁY MÓC

      sheet1.appendRow([TextCellValue('2. THỐNG KÊ MÁY MÓC')]);

      sheet1.appendRow([
        TextCellValue('Tổng số máy:'),
        IntCellValue(machineProvider.machines.length),
      ]);

      final goodMachines = machineProvider.machines
          .where((m) => m.status == 'Tốt')
          .length;

      sheet1.appendRow([
        TextCellValue('Đang hoạt động tốt:'),
        IntCellValue(goodMachines),
      ]);

      double totalHours = 0;

      for (final machine in machineProvider.machines) {
        totalHours += _toDouble(machine.totalHours);
      }

      sheet1.appendRow([
        TextCellValue('Tổng giờ vận hành:'),
        DoubleCellValue(totalHours),
      ]);

      _addEmptyRow(sheet1);

      // NHÂN SỰ

      sheet1.appendRow([TextCellValue('3. THỐNG KÊ NHÂN SỰ')]);

      sheet1.appendRow([
        TextCellValue('Tổng nhân viên:'),
        IntCellValue(employeeProvider.employees.length),
      ]);

      final activeEmployees = employeeProvider.employees
          .where((e) => e.isActive)
          .length;

      sheet1.appendRow([
        TextCellValue('Đang làm:'),
        IntCellValue(activeEmployees),
      ]);

      _addEmptyRow(sheet1);

      // TÀI CHÍNH

      sheet1.appendRow([TextCellValue('4. THỐNG KÊ TÀI CHÍNH')]);

      sheet1.appendRow([
        TextCellValue('Tổng thu:'),
        DoubleCellValue(_toDouble(financeProvider.getTotalRevenue())),
      ]);

      sheet1.appendRow([
        TextCellValue('Tổng chi:'),
        DoubleCellValue(_toDouble(financeProvider.getTotalCost())),
      ]);

      sheet1.appendRow([
        TextCellValue('Lợi nhuận:'),
        DoubleCellValue(_toDouble(financeProvider.getTotalProfit())),
      ]);

      _addEmptyRow(sheet1);

      // NHIÊN LIỆU

      sheet1.appendRow([TextCellValue('5. THỐNG KÊ NHIÊN LIỆU')]);

      sheet1.appendRow([
        TextCellValue('Số loại nhiên liệu:'),
        IntCellValue(fuelProvider.fuels.length),
      ]);

      sheet1.appendRow([
        TextCellValue('Tổng giá trị tồn:'),
        DoubleCellValue(_toDouble(fuelProvider.getTotalStockValue())),
      ]);

      _applyFormatting(sheet1);

      // ----------------------------------------------------------
      // SHEET 2: CHI TIẾT KHO
      // ----------------------------------------------------------

      final sheet2 = excel['CHI TIẾT KHO'];

      _addTitle(sheet2, 'DANH SÁCH VẬT TƯ TRONG KHO');

      _addEmptyRow(sheet2);

      _addHeader(sheet2, [
        'Mã hàng',
        'Tên hàng',
        'Đơn vị',
        'Đơn giá',
        'Nhà cung cấp',
        'Tồn kho',
        'Giá trị',
      ]);

      for (final item in warehouseProvider.items) {
        final stock = _toDouble(item.stock);

        final importPrice = _toDouble(item.importPrice);

        sheet2.appendRow([
          TextCellValue(item.id),
          TextCellValue(item.name),
          TextCellValue(item.unit),
          DoubleCellValue(importPrice),
          TextCellValue(item.supplier),
          DoubleCellValue(stock),
          DoubleCellValue(stock * importPrice),
        ]);
      }

      _applyFormatting(sheet2);

      // ----------------------------------------------------------
      // SHEET 3: CHI TIẾT MÁY MÓC
      // ----------------------------------------------------------

      final sheet3 = excel['CHI TIẾT MÁY MÓC'];

      _addTitle(sheet3, 'DANH SÁCH MÁY MÓC');

      _addEmptyRow(sheet3);

      _addHeader(sheet3, [
        'Mã máy',
        'Tên máy',
        'Loại',
        'Hãng',
        'Năm SX',
        'Trạng thái',
        'Tổng giờ',
        'Nhiên liệu',
      ]);

      for (final machine in machineProvider.machines) {
        sheet3.appendRow([
          TextCellValue(machine.id),
          TextCellValue(machine.name),
          TextCellValue(machine.type),
          TextCellValue(machine.manufacturer),
          IntCellValue(_toInt(machine.year)),
          TextCellValue(machine.status),
          DoubleCellValue(_toDouble(machine.totalHours)),
          DoubleCellValue(_toDouble(machine.fuelConsumption)),
        ]);
      }

      _applyFormatting(sheet3);

      // ----------------------------------------------------------
      // SHEET 4: CHI TIẾT NHÂN SỰ
      // ----------------------------------------------------------

      final sheet4 = excel['CHI TIẾT NHÂN SỰ'];

      _addTitle(sheet4, 'DANH SÁCH NHÂN VIÊN');

      _addEmptyRow(sheet4);

      _addHeader(sheet4, [
        'Mã NV',
        'Họ tên',
        'Vị trí',
        'Bộ phận',
        'Lương/ngày',
        'SĐT',
        'Trạng thái',
      ]);

      for (final emp in employeeProvider.employees) {
        sheet4.appendRow([
          TextCellValue(emp.id),
          TextCellValue(emp.name),
          TextCellValue(emp.position),
          TextCellValue(emp.department),
          DoubleCellValue(_toDouble(emp.dailyRate)),
          TextCellValue(emp.phone),
          TextCellValue(emp.isActive ? 'Đang làm' : 'Nghỉ'),
        ]);
      }

      _applyFormatting(sheet4);

      // ----------------------------------------------------------
      // SHEET 5: CHI TIẾT TÀI CHÍNH
      // ----------------------------------------------------------

      final sheet5 = excel['CHI TIẾT TÀI CHÍNH'];

      _addTitle(sheet5, 'LỢI NHUẬN THEO LÔ');

      _addEmptyRow(sheet5);

      _addHeader(sheet5, [
        'Mã lô',
        'Tên lô',
        'Tổng thu',
        'Tổng chi',
        'Lợi nhuận',
        'Tỷ suất (%)',
      ]);

      for (final report in financeProvider.generateProfitReport()) {
        sheet5.appendRow([
          TextCellValue(report.fieldId),
          TextCellValue(report.fieldName),
          DoubleCellValue(_toDouble(report.totalRevenue)),
          DoubleCellValue(_toDouble(report.totalCost)),
          DoubleCellValue(_toDouble(report.profit)),
          DoubleCellValue(_toDouble(report.profitMargin)),
        ]);
      }

      _applyFormatting(sheet5);

      await saveExcelFile(excel, 'BaoCaoTongHopHeThong.xlsx');
    } catch (e) {
      print('Lỗi xuất báo cáo tổng hợp hệ thống: $e');
      rethrow;
    }
  }

  // ============================================================
  // HÀM THÊM TIÊU ĐỀ
  // ============================================================

  static void _addTitle(Sheet sheet, String title) {
    sheet.appendRow([TextCellValue(title)]);
  }

  // ============================================================
  // HÀM THÊM DÒNG TRỐNG
  // ============================================================

  static void _addEmptyRow(Sheet sheet) {
    sheet.appendRow([]);
  }

  // ============================================================
  // HÀM THÊM HEADER
  // ============================================================

  static void _addHeader(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((header) => TextCellValue(header)).toList());
  }

  // ============================================================
  // ĐỊNH DẠNG CỘT
  // ============================================================

  static void _applyFormatting(Sheet sheet) {
    for (int i = 0; i < 12; i++) {
      sheet.setColumnWidth(i, 20);
    }
  }

  // ============================================================
  // CHUYỂN SỐ SANG DOUBLE
  // ============================================================

  static double _toDouble(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0.0;
  }

  // ============================================================
  // CHUYỂN SANG INT
  // ============================================================

  static int _toInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  // ============================================================
  // ĐỊNH DẠNG NGÀY
  // ============================================================

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  // ============================================================
  // ĐỊNH DẠNG NGÀY + GIỜ
  // ============================================================

  static String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/${date.year} '
        '$hour:$minute';
  }

  // ============================================================
  // CHUYỂN TransactionType THÀNH TEXT
  // ============================================================

  static String _transactionTypeName(TransactionType type) {
    final value = type.toString();

    if (value.contains('.')) {
      return value.split('.').last;
    }

    return value;
  }
}
