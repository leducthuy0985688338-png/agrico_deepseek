import 'package:excel/excel.dart';
import '../../../core/reports/excel_report_layout.dart';
import '../domain/personnel.dart';

class PersonnelReport {
  const PersonnelReport({
    required this.farmId,
    required this.period,
    required this.employees,
    required this.entries,
    required this.payrolls,
    required this.payments,
    required this.laborCosts,
    this.workerId,
    this.adjustments = const [],
    this.refunds = const [],
  });
  final String farmId, period;
  final String? workerId;
  final List<EmployeeCard> employees;
  final List<LaborEntryRecord> entries;
  final List<PayrollRecordV2> payrolls;
  final List<SalaryPayment> payments;
  final List<PayrollAdjustmentRecord> adjustments;
  final List<PayrollRefund> refunds;
  final List<ProductionLaborCost> laborCosts;
  List<LaborEntryRecord> get selectedEntries => entries
      .where(
        (e) =>
            e.businessDay.startsWith('$period-') &&
            (workerId == null || workerId == e.workerId),
      )
      .toList();
  List<PayrollRecordV2> get selectedPayrolls => payrolls
      .where(
        (p) =>
            p.period == period && (workerId == null || p.workerId == workerId),
      )
      .toList();
  Excel workbook() {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      throw const FormatException('Invalid period.');
    }
    final excel = Excel.createExcel();
    void row(Sheet sheet, List<String> values, {Set<int> numbers = const {}}) {
      sheet.appendRow([
        for (var i = 0; i < values.length; i++)
          if (numbers.contains(i) &&
              values[i].replaceAll(RegExp(r'[-.]'), '').length <= 15)
            if (values[i].contains('.'))
              DoubleCellValue(double.parse(values[i]))
            else
              IntCellValue(int.parse(values[i]))
          else
            TextCellValue(values[i]),
      ]);
    }

    final info = excel['THONG TIN'];
    for (final data in [
      ['AGRICO', 'Nhân sự, chấm công và tiền lương'],
      ['Farm', farmId],
      ['Kỳ lương / Attendance month', period],
      ['Worker', workerId ?? 'All'],
      ['Exported UTC', DateTime.now().toUtc().toIso8601String()],
      ['Business timezone', 'UTC+7; overnight attendance belongs to start day'],
      [
        'Scope',
        'Attendance includes draft/void status; earnings and production costs use approved sources only.',
      ],
      [
        'Payments',
        'Paid/outstanding salary reflects payments recorded up to export time; payment history is listed separately.',
      ],
      [
        'Money',
        'VND and LAK separate. Explicit pay-rate precision/rounding; long exact decimals are text beyond Excel 15 digits.',
      ],
      [
        'Machine labor',
        'Wages inside all-inclusive machine shifts remain payable but are excluded from production labor allocation.',
      ],
      [
        'Allocation',
        'Source money balanced by largest remainders; unpaid payroll is distinct from unallocated production costs.',
      ],
    ]) {
      row(info, data);
    }
    final staff = excel['DANH SACH NV'];
    row(staff, [
      'Mã NV',
      'ID dùng chung',
      'Họ tên',
      'Trạng thái',
      'Vị trí',
      'Bộ phận',
      'Điện thoại',
      'Địa chỉ',
      'Ngày sinh',
      'Giới tính',
      'Giấy tờ',
      'Bắt đầu HĐ',
      'Kết thúc HĐ',
      'Ngân hàng',
      'Tài khoản',
    ]);
    for (final e in employees.where(
      (e) => workerId == null || workerId == e.workerId,
    )) {
      final d = e.profile?.details ?? const <String, String>{};
      row(staff, [
        e.code,
        e.workerId,
        e.name,
        e.active ? 'Active' : 'Inactive',
        for (final k in [
          'position',
          'department',
          'phone',
          'address',
          'birthOn',
          'gender',
          'identityNo',
          'contractStart',
          'contractEnd',
          'bankName',
          'bankAccount',
        ])
          d[k] ?? '',
      ]);
    }
    final attendance = excel['CHAM CONG'];
    row(attendance, [
      'Ngày Lào',
      'Mã nguồn',
      'Nhân viên',
      'Bắt đầu UTC',
      'Kết thúc UTC',
      'Nghỉ (phút)',
      'Thường (phút)',
      'Tăng ca (phút)',
      'Phút/công chuẩn',
      'Lượng khoán',
      'Đơn vị khoán',
      'Trạng thái',
      'Lương thường',
      'Tăng ca',
      'Lương khoán',
      'Tổng nguồn',
      'Tiền tệ',
      'Đã phân bổ vào kế hoạch',
      'Chưa phân bổ',
      'Đã gồm trong ca máy',
    ]);
    for (final e in selectedEntries) {
      final allocated = LaborMoney.sum(
        laborCosts.where((c) => c.entryId == e.id).map((c) => c.amount),
      );
      final unallocated = e.total == null
          ? ''
          : e.machineId != null
          ? '0'
          : LaborMoney.minus(e.total!, allocated);
      row(
        attendance,
        [
          e.businessDay,
          e.id,
          e.workerName,
          e.startsAt.toUtc().toIso8601String(),
          e.endsAt.toUtc().toIso8601String(),
          e.breakMinutes.toString(),
          e.regularMinutes.toString(),
          e.overtimeMinutes.toString(),
          e.standardMinutes?.toString() ?? '',
          e.pieceQuantity ?? '',
          e.pieceUnit ?? '',
          e.status,
          e.regularAmount ?? '',
          e.overtimeAmount ?? '',
          e.pieceAmount ?? '',
          e.total ?? '',
          e.currency ?? '',
          e.status == 'approved' ? allocated : '',
          e.status == 'approved' ? unallocated : '',
          e.machineId ?? '',
        ],
        numbers: {
          5,
          6,
          7,
          if (e.standardMinutes != null) 8,
          if (e.pieceQuantity != null) 9,
          if (e.total != null) ...{12, 13, 14, 15},
          if (e.status == 'approved') ...{17, 18},
        },
      );
    }
    final salary = excel['BANG LUONG'];
    row(salary, [
      'ID bảng lương',
      'Nhân viên',
      'ID nhân viên',
      'Kỳ',
      'Tiền tệ',
      'Trạng thái',
      'Thường',
      'Tăng ca',
      'Khoán',
      'Phụ cấp',
      'Thưởng',
      'Tạm ứng',
      'Khấu trừ',
      'Thực lĩnh',
      'Đã trả đến lúc xuất',
      'Còn phải trả',
      'Kế hoạch nhận phụ cấp/thưởng',
      'Lý do điều chỉnh',
      'Mã bảng lương',
      'Điều chỉnh đã duyệt',
      'Thực lĩnh hiệu lực',
      'Đã thu hoàn ròng',
      'Nhân viên phải hoàn',
    ]);
    for (final p in selectedPayrolls) {
      row(
        salary,
        [
          p.id,
          p.workerName,
          p.workerId,
          p.period,
          p.currency,
          p.status,
          p.regular,
          p.overtime,
          p.piece,
          p.allowance,
          p.bonus,
          p.advance,
          p.deduction,
          p.net,
          p.paid,
          p.payable,
          p.adjustmentPlanId ?? 'Unallocated',
          p.note,
          p.code,
          p.adjustmentTotal,
          p.effectiveNet,
          p.refunded,
          p.overpaid,
        ],
        numbers: {6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20, 21, 22},
      );
    }
    final sourcePayroll = {for (final p in payrolls) p.id: p};
    final adjustmentSheet = excel['DIEU CHINH LUONG'];
    row(adjustmentSheet, [
      'Mã điều chỉnh',
      'Bảng lương gốc',
      'Nhân viên',
      'Ngày hạch toán',
      'Tiền tệ',
      'Loại',
      'Tăng/giảm',
      'Trạng thái',
      'Lý do',
      'Người lập',
      'Người duyệt',
      'Chi phí phân bổ',
    ]);
    final selectedAdjustments = adjustments
        .where(
          (a) =>
              a.draft.day.startsWith('$period-') &&
              (workerId == null ||
                  sourcePayroll[a.draft.payrollId]?.workerId == workerId),
        )
        .toList();
    for (final a in selectedAdjustments) {
      row(
        adjustmentSheet,
        [
          a.code,
          sourcePayroll[a.draft.payrollId]?.code ?? a.draft.payrollId,
          sourcePayroll[a.draft.payrollId]?.workerName ?? '',
          a.draft.day,
          a.draft.currency,
          a.draft.kind.name,
          a.draft.delta,
          a.status,
          a.draft.reason,
          a.creator,
          a.approver ?? '',
          a.draft.costDelta,
        ],
        numbers: {6, 11},
      );
    }
    final refundSheet = excel['THU HOAN LUONG'];
    row(refundSheet, [
      'Ngày',
      'ID',
      'Bảng lương gốc',
      'Nhân viên',
      'Tiền tệ',
      'Số tiền',
      'Loại',
      'Đảo nguồn',
      'Lý do',
      'Người ghi',
      'Phiếu tiền',
    ]);
    for (final r in refunds.where(
      (r) =>
          r.day.startsWith('$period-') &&
          (workerId == null ||
              sourcePayroll[r.payrollId]?.workerId == workerId),
    )) {
      row(
        refundSheet,
        [
          r.day,
          r.id,
          sourcePayroll[r.payrollId]?.code ?? r.payrollId,
          sourcePayroll[r.payrollId]?.workerName ?? '',
          r.currency,
          r.amount,
          r.reversesId == null ? 'THU' : 'ĐẢO THU',
          r.reversesId ?? '',
          r.reason,
          r.actor,
          r.financeId,
        ],
        numbers: {5},
      );
    }
    final payment = excel['CHI TRA LUONG'];
    row(payment, [
      'Ngày',
      'ID thanh toán',
      'ID bảng lương',
      'Nhân viên',
      'Tiền tệ',
      'Số tiền',
      'Tham chiếu/lý do',
      'Mã bảng lương',
    ]);
    final salaryById = {for (final p in selectedPayrolls) p.id: p};
    for (final p in payments.where(
      (p) => salaryById.containsKey(p.payrollId),
    )) {
      row(
        payment,
        [
          p.day,
          p.id,
          p.payrollId,
          salaryById[p.payrollId]!.workerName,
          p.currency,
          p.amount,
          p.reversed ? 'REVERSED · ${p.note}' : p.note,
          salaryById[p.payrollId]!.code,
        ],
        numbers: {5},
      );
    }
    final productivity = excel['NANG SUAT LD'];
    row(productivity, [
      'Ngày',
      'Nhân viên',
      'Nguồn',
      'Phút thường',
      'Phút tăng ca',
      'Khối lượng được duyệt',
      'Đơn vị',
      'Năng suất (lượng/giờ)',
      'Ghi chú',
    ]);
    for (final e in selectedEntries.where(
      (e) => e.status == 'approved' && e.productivityQuantity != null,
    )) {
      row(
        productivity,
        [
          e.businessDay,
          e.workerName,
          e.id,
          e.regularMinutes.toString(),
          e.overtimeMinutes.toString(),
          e.productivityQuantity!,
          e.productivityUnit ?? '',
          LaborMoney.fraction(
            e.productivityQuantity!,
            60,
            e.regularMinutes + e.overtimeMinutes,
            6,
            MoneyRounding.halfUp,
          ),
          'Approved output per source; do not combine different work units or infer ratings',
        ],
        numbers: {3, 4, 5, 7},
      );
    }
    final costs = excel['PHAN BO NHAN CONG'];
    row(costs, [
      'Ngày nguồn',
      'ID nguồn',
      'Kế hoạch',
      'Phút thường',
      'Phút tăng ca',
      'Chi phí',
      'Tiền tệ',
    ]);
    final entryIds = selectedEntries.map((e) => e.id).toSet();
    final payrollIds = selectedPayrolls.map((p) => 'payroll:${p.id}').toSet();
    final correctionCostIds = {
      for (final a in selectedAdjustments)
        for (final c in a.draft.allocations)
          'payroll-adjustment:${a.draft.id}:${c.planId}',
    };
    for (final c in laborCosts.where(
      (c) =>
          entryIds.contains(c.entryId) ||
          payrollIds.contains(c.entryId) ||
          correctionCostIds.contains(c.entryId),
    )) {
      row(
        costs,
        [
          c.businessDay,
          c.entryId,
          c.planId,
          c.regularMinutes.toString(),
          c.overtimeMinutes.toString(),
          c.amount,
          c.currency,
        ],
        numbers: {3, 4, 5, 7},
      );
    }
    final totals = excel['TONG HOP'];
    row(totals, [
      'Tiền tệ',
      'Lương thực lĩnh đã duyệt',
      'Đã trả',
      'Còn phải trả',
      'Chi phí đã phân bổ vào kế hoạch',
      'Nhân viên phải hoàn',
    ]);
    for (final currency in ['VND', 'LAK']) {
      final payroll = selectedPayrolls.where(
        (p) => p.currency == currency && p.status == 'approved',
      );
      row(
        totals,
        [
          currency,
          LaborMoney.sum(payroll.map((p) => p.effectiveNet)),
          LaborMoney.sum(payroll.map((p) => p.paid)),
          LaborMoney.sum(payroll.map((p) => p.payable)),
          LaborMoney.sum(
            laborCosts
                .where(
                  (c) =>
                      c.currency == currency &&
                      (entryIds.contains(c.entryId) ||
                          payrollIds.contains(c.entryId) ||
                          correctionCostIds.contains(c.entryId)),
                )
                .map((c) => c.amount),
          ),
          LaborMoney.sum(payroll.map((p) => p.overpaid)),
        ],
        numbers: {1, 2, 3, 4, 5},
      );
    }
    if (excel.getDefaultSheet() == 'Sheet1') excel.delete('Sheet1');
    for (final sheet in excel.tables.values) {
      sheet.setRowHeight(0, 40);
      for (var col = 0; col < sheet.maxColumns; col++) {
        sheet.setColumnWidth(col, 26);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
            .cellStyle = CellStyle(
          bold: true,
          textWrapping: TextWrapping.WrapText,
          backgroundColorHex: ExcelColor.fromHexString('#DDEEDB'),
        );
      }
    }
    return excel;
  }

  List<int> bytes() => encodeReportWorkbook(workbook());
}
