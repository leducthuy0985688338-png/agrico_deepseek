import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';

class AIService {
  static String processQuestion(
    String question,
    WarehouseProvider warehouseProvider,
    MachineProvider machineProvider,
    EmployeeProvider employeeProvider,
    FinanceProvider financeProvider,
    FuelProvider fuelProvider,
  ) {
    final lowerQuestion = question.toLowerCase();

    // ====== CÂU HỎI VỀ KHO ======
    if (lowerQuestion.contains('tồn kho') ||
        lowerQuestion.contains('kho còn') ||
        lowerQuestion.contains('hàng tồn')) {
      return _handleWarehouseQuery(question, warehouseProvider);
    }

    // ====== CÂU HỎI VỀ MÁY MÓC ======
    if (lowerQuestion.contains('máy') ||
        lowerQuestion.contains('thiết bị') ||
        lowerQuestion.contains('xe')) {
      return _handleMachineQuery(question, machineProvider);
    }

    // ====== CÂU HỎI VỀ NHÂN SỰ ======
    if (lowerQuestion.contains('nhân sự') ||
        lowerQuestion.contains('nhân viên') ||
        lowerQuestion.contains('công nhân') ||
        lowerQuestion.contains('lương')) {
      return _handleEmployeeQuery(question, employeeProvider);
    }

    // ====== CÂU HỎI VỀ TÀI CHÍNH ======
    if (lowerQuestion.contains('tài chính') ||
        lowerQuestion.contains('thu') ||
        lowerQuestion.contains('chi') ||
        lowerQuestion.contains('lợi nhuận') ||
        lowerQuestion.contains('doanh thu')) {
      return _handleFinanceQuery(question, financeProvider);
    }

    // ====== CÂU HỎI VỀ NHIÊN LIỆU ======
    if (lowerQuestion.contains('nhiên liệu') ||
        lowerQuestion.contains('dầu') ||
        lowerQuestion.contains('xăng')) {
      return _handleFuelQuery(question, fuelProvider);
    }

    // ====== CÂU HỎI TỔNG HỢP ======
    if (lowerQuestion.contains('tổng quan') ||
        lowerQuestion.contains('báo cáo') ||
        lowerQuestion.contains('thống kê')) {
      return _handleSummaryQuery(
        warehouseProvider,
        machineProvider,
        employeeProvider,
        financeProvider,
        fuelProvider,
      );
    }

    // ====== CÂU HỎI CHÀO HỎI ======
    if (lowerQuestion.contains('xin chào') ||
        lowerQuestion.contains('chào') ||
        lowerQuestion.contains('hello') ||
        lowerQuestion.contains('hi')) {
      return 'Xin chào! Tôi là trợ lý AI của Agrico. Tôi có thể giúp bạn tra cứu thông tin về:\n'
          '📦 Tồn kho\n'
          '🚜 Máy móc\n'
          '👨‍💼 Nhân sự\n'
          '💰 Tài chính\n'
          '⛽ Nhiên liệu\n'
          'Bạn muốn hỏi gì?';
    }

    // ====== KHÔNG HIỂU CÂU HỎI ======
    return 'Xin lỗi, tôi chưa hiểu câu hỏi của bạn. Tôi có thể trả lời các câu hỏi về:\n'
        '📦 Tồn kho: "Kho còn bao nhiêu Phân Kali?"\n'
        '🚜 Máy móc: "Máy cày Yanmar đang ở trạng thái nào?"\n'
        '👨‍💼 Nhân sự: "Tổng số nhân viên là bao nhiêu?"\n'
        '💰 Tài chính: "Lợi nhuận tháng này là bao nhiêu?"\n'
        '⛽ Nhiên liệu: "Còn bao nhiêu Dầu Diesel?"\n'
        '📊 Tổng quan: "Thống kê tổng quan"';
  }

  // ====== XỬ LÝ CÂU HỎI VỀ KHO ======
  static String _handleWarehouseQuery(
    String question,
    WarehouseProvider provider,
  ) {
    final lowerQuestion = question.toLowerCase();

    // Tìm kiếm theo tên hàng
    for (var item in provider.items) {
      if (lowerQuestion.contains(item.name.toLowerCase()) ||
          lowerQuestion.contains(item.id.toLowerCase())) {
        return '📦 ${item.name} (${item.id}):\n'
            'Tồn kho: ${item.stock} ${item.unit}\n'
            'Đơn giá: ${item.importPrice.toStringAsFixed(0)} VND/${item.unit}\n'
            'Nhà cung cấp: ${item.supplier}';
      }
    }

    // Tổng quan kho
    int totalItems = provider.items.length;
    int totalStock = provider.items.fold(0, (sum, item) => sum + item.stock);
    double totalValue = provider.items.fold(
      0.0,
      (sum, item) => sum + item.stock * item.importPrice,
    );

    return '📊 TỔNG QUAN KHO:\n'
            'Số loại hàng: $totalItems\n'
            'Tổng số lượng: $totalStock\n'
            'Tổng giá trị: ${totalValue.toStringAsFixed(0)} VND\n\n'
            '📋 DANH SÁCH CHI TIẾT:\n' +
        provider.items
            .map((item) => '• ${item.name}: ${item.stock} ${item.unit}')
            .join('\n');
  }

  // ====== XỬ LÝ CÂU HỎI VỀ MÁY MÓC ======
  static String _handleMachineQuery(String question, MachineProvider provider) {
    final lowerQuestion = question.toLowerCase();

    // Tìm kiếm theo tên máy
    for (var machine in provider.machines) {
      if (lowerQuestion.contains(machine.name.toLowerCase()) ||
          lowerQuestion.contains(machine.id.toLowerCase())) {
        return '🚜 ${machine.name} (${machine.id}):\n'
            'Loại: ${machine.type}\n'
            'Hãng: ${machine.manufacturer}\n'
            'Trạng thái: ${machine.status}\n'
            'Tổng giờ: ${machine.totalHours}h\n'
            'Nhiên liệu: ${machine.fuelConsumption} L/h\n'
            'Đang làm tại: ${machine.currentFieldId ?? "Không"}';
      }
    }

    // Thống kê máy móc
    int total = provider.machines.length;
    int good = provider.machines.where((m) => m.status == 'Tốt').length;
    int maintenance = provider.machines
        .where((m) => m.status == 'Đang bảo trì')
        .length;
    int broken = provider.machines.where((m) => m.status == 'Hỏng').length;
    int totalHours = provider.machines.fold(0, (sum, m) => sum + m.totalHours);

    return '📊 TỔNG QUAN MÁY MÓC:\n'
            'Tổng số máy: $total\n'
            '✅ Đang hoạt động tốt: $good\n'
            '🔧 Đang bảo trì: $maintenance\n'
            '❌ Bị hỏng: $broken\n'
            'Tổng giờ vận hành: $totalHours h\n\n'
            '📋 DANH SÁCH CHI TIẾT:\n' +
        provider.machines
            .map((m) => '• ${m.name}: ${m.status} - ${m.totalHours}h')
            .join('\n');
  }

  // ====== XỬ LÝ CÂU HỎI VỀ NHÂN SỰ ======
  static String _handleEmployeeQuery(
    String question,
    EmployeeProvider provider,
  ) {
    final lowerQuestion = question.toLowerCase();

    // Tìm kiếm theo tên nhân viên
    for (var emp in provider.employees) {
      if (lowerQuestion.contains(emp.name.toLowerCase()) ||
          lowerQuestion.contains(emp.id.toLowerCase())) {
        return '👨‍💼 ${emp.name} (${emp.id}):\n'
            'Vị trí: ${emp.position}\n'
            'Bộ phận: ${emp.department}\n'
            'Lương: ${emp.dailyRate.toStringAsFixed(0)} VND/ngày\n'
            'Trạng thái: ${emp.isActive ? "Đang làm" : "Nghỉ"}\n'
            'SĐT: ${emp.phone}';
      }
    }

    // Thống kê nhân sự
    int total = provider.employees.length;
    int active = provider.employees.where((e) => e.isActive).length;
    int production = provider.getEmployeesByDepartment('Sản xuất').length;
    int office = provider.getEmployeesByDepartment('Văn phòng').length;

    return '📊 TỔNG QUAN NHÂN SỰ:\n'
            'Tổng nhân viên: $total\n'
            '✅ Đang làm: $active\n'
            '🏭 Sản xuất: $production\n'
            '🏢 Văn phòng: $office\n\n'
            '📋 DANH SÁCH CHI TIẾT:\n' +
        provider.employees
            .map(
              (e) =>
                  '• ${e.name}: ${e.position} - ${e.isActive ? "Đang làm" : "Nghỉ"}',
            )
            .join('\n');
  }

  // ====== XỬ LÝ CÂU HỎI VỀ TÀI CHÍNH ======
  static String _handleFinanceQuery(String question, FinanceProvider provider) {
    final lowerQuestion = question.toLowerCase();

    // Hỏi về lợi nhuận
    if (lowerQuestion.contains('lợi nhuận') ||
        lowerQuestion.contains('lãi') ||
        lowerQuestion.contains('lời')) {
      final reports = provider.generateProfitReport();
      if (reports.isEmpty) {
        return 'Chưa có dữ liệu lợi nhuận.';
      }

      String result = '📊 BÁO CÁO LỢI NHUẬN:\n\n';
      for (var report in reports) {
        result +=
            '📍 ${report.fieldName}:\n'
            'Thu: ${report.totalRevenue.toStringAsFixed(0)} VND\n'
            'Chi: ${report.totalCost.toStringAsFixed(0)} VND\n'
            '${report.profit >= 0 ? "📈" : "📉"} Lợi nhuận: ${report.profit >= 0 ? "+" : ""}${report.profit.toStringAsFixed(0)} VND (${report.profitMargin.toStringAsFixed(1)}%)\n\n';
      }
      return result;
    }

    // Tổng quan tài chính
    double totalRevenue = provider.getTotalRevenue();
    double totalCost = provider.getTotalCost();
    double profit = provider.getTotalProfit();

    return '💰 TỔNG QUAN TÀI CHÍNH:\n'
            'Tổng thu: ${totalRevenue.toStringAsFixed(0)} VND\n'
            'Tổng chi: ${totalCost.toStringAsFixed(0)} VND\n'
            '${profit >= 0 ? "📈" : "📉"} Lợi nhuận: ${profit >= 0 ? "+" : ""}${profit.toStringAsFixed(0)} VND\n\n'
            '📋 CHI TIẾT THEO LÔ:\n' +
        provider
            .generateProfitReport()
            .map(
              (r) =>
                  '• ${r.fieldName}: ${r.profit >= 0 ? "+" : ""}${r.profit.toStringAsFixed(0)} VND',
            )
            .join('\n');
  }

  // ====== XỬ LÝ CÂU HỎI VỀ NHIÊN LIỆU ======
  static String _handleFuelQuery(String question, FuelProvider provider) {
    final lowerQuestion = question.toLowerCase();

    // Tìm kiếm theo loại nhiên liệu
    for (var fuel in provider.fuels) {
      if (lowerQuestion.contains(fuel.name.toLowerCase()) ||
          lowerQuestion.contains(fuel.id.toLowerCase())) {
        return '⛽ ${fuel.name} (${fuel.id}):\n'
            'Tồn kho: ${fuel.stock} ${fuel.unit}\n'
            'Đơn giá: ${fuel.unitPrice.toStringAsFixed(0)} VND/${fuel.unit}\n'
            'Nhà cung cấp: ${fuel.supplier}\n'
            'Tổng giá trị: ${(fuel.stock * fuel.unitPrice).toStringAsFixed(0)} VND';
      }
    }

    // Tổng quan nhiên liệu
    double totalValue = provider.getTotalStockValue();
    int totalTypes = provider.fuels.length;

    return '⛽ TỔNG QUAN NHIÊN LIỆU:\n'
            'Số loại: $totalTypes\n'
            'Tổng giá trị tồn: ${totalValue.toStringAsFixed(0)} VND\n\n'
            '📋 DANH SÁCH CHI TIẾT:\n' +
        provider.fuels
            .map(
              (f) =>
                  '• ${f.name}: ${f.stock} ${f.unit} - ${f.unitPrice.toStringAsFixed(0)} VND/${f.unit}',
            )
            .join('\n');
  }

  // ====== XỬ LÝ CÂU HỎI TỔNG HỢP ======
  static String _handleSummaryQuery(
    WarehouseProvider warehouseProvider,
    MachineProvider machineProvider,
    EmployeeProvider employeeProvider,
    FinanceProvider financeProvider,
    FuelProvider fuelProvider,
  ) {
    return '📊 BÁO CÁO TỔNG HỢP TRANG TRẠI\n'
        '═══════════════════════════════\n\n'
        '📦 KHO:\n'
        '• Số loại hàng: ${warehouseProvider.items.length}\n'
        '• Tổng giá trị: ${warehouseProvider.items.fold(0.0, (sum, item) => sum + item.stock * item.importPrice).toStringAsFixed(0)} VND\n\n'
        '🚜 MÁY MÓC:\n'
        '• Tổng số máy: ${machineProvider.machines.length}\n'
        '• Đang hoạt động: ${machineProvider.machines.where((m) => m.status == "Tốt").length}\n'
        '• Tổng giờ vận hành: ${machineProvider.machines.fold(0, (sum, m) => sum + m.totalHours)} h\n\n'
        '👨‍💼 NHÂN SỰ:\n'
        '• Tổng nhân viên: ${employeeProvider.employees.length}\n'
        '• Đang làm: ${employeeProvider.employees.where((e) => e.isActive).length}\n\n'
        '💰 TÀI CHÍNH:\n'
        '• Tổng thu: ${financeProvider.getTotalRevenue().toStringAsFixed(0)} VND\n'
        '• Tổng chi: ${financeProvider.getTotalCost().toStringAsFixed(0)} VND\n'
        '• Lợi nhuận: ${financeProvider.getTotalProfit() >= 0 ? "+" : ""}${financeProvider.getTotalProfit().toStringAsFixed(0)} VND\n\n'
        '⛽ NHIÊN LIỆU:\n'
        '• Số loại: ${fuelProvider.fuels.length}\n'
        '• Tổng giá trị tồn: ${fuelProvider.getTotalStockValue().toStringAsFixed(0)} VND';
  }
}
