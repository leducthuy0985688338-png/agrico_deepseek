import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';
import '../services/report_service.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final warehouseProvider = context.read<WarehouseProvider>();
    final machineProvider = context.read<MachineProvider>();
    final employeeProvider = context.read<EmployeeProvider>();
    final financeProvider = context.read<FinanceProvider>();
    final fuelProvider = context.read<FuelProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ====== TIÊU ĐỀ ======
          const Text(
            '📊 Xuất báo cáo Excel',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn loại báo cáo bạn muốn xuất',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // ====== BÁO CÁO TÀI CHÍNH ======
          _buildSectionTitle('💰 Báo cáo Tài chính'),

          _buildReportCard(
            context,
            icon: Icons.money,
            title: 'Báo cáo Tài chính tổng hợp',
            subtitle: 'Xuất báo cáo thu chi, lợi nhuận toàn bộ hệ thống',
            color: Colors.green,
            onTap: () async {
              try {
                await ReportService.exportFinanceReport(financeProvider);
                _showSuccess(context, 'Đã xuất báo cáo tài chính!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          _buildReportCard(
            context,
            icon: Icons.map,
            title: 'Báo cáo Tài chính theo lô',
            subtitle: 'Xuất báo cáo thu chi theo từng lô đất',
            color: Colors.blue,
            onTap: () {
              _showFieldSelectionDialog(context, financeProvider);
            },
          ),

          const SizedBox(height: 16),

          // ====== BÁO CÁO TỔNG HỢP HỆ THỐNG ======
          _buildSectionTitle('📋 Báo cáo Tổng hợp hệ thống'),

          _buildReportCard(
            context,
            icon: Icons.summarize,
            title: 'Báo cáo Tổng hợp toàn bộ',
            subtitle:
                'Xuất tất cả dữ liệu: Kho, Máy móc, Nhân sự, Tài chính, Nhiên liệu',
            color: Colors.purple,
            onTap: () async {
              try {
                await ReportService.exportFullSystemReport(
                  warehouseProvider,
                  machineProvider,
                  employeeProvider,
                  financeProvider,
                  fuelProvider,
                );
                _showSuccess(context, 'Đã xuất báo cáo tổng hợp!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          const SizedBox(height: 16),

          // ====== BÁO CÁO CŨ ======
          _buildSectionTitle('📦 Các báo cáo khác'),

          _buildReportCard(
            context,
            icon: Icons.inventory,
            title: 'Báo cáo Tồn kho',
            subtitle: 'Xuất danh sách vật tư trong kho',
            color: Colors.blue,
            onTap: () async {
              try {
                await ReportService.exportWarehouseReport(warehouseProvider);
                _showSuccess(context, 'Đã xuất báo cáo tồn kho!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          _buildReportCard(
            context,
            icon: Icons.agriculture,
            title: 'Báo cáo Máy móc',
            subtitle: 'Xuất danh sách và trạng thái máy móc',
            color: Colors.orange,
            onTap: () async {
              try {
                await ReportService.exportMachineReport(machineProvider);
                _showSuccess(context, 'Đã xuất báo cáo máy móc!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          _buildReportCard(
            context,
            icon: Icons.people,
            title: 'Báo cáo Nhân sự',
            subtitle: 'Xuất danh sách nhân viên và thông tin',
            color: Colors.purple,
            onTap: () async {
              try {
                await ReportService.exportEmployeeReport(employeeProvider);
                _showSuccess(context, 'Đã xuất báo cáo nhân sự!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          const SizedBox(height: 24),

          // ====== HƯỚNG DẪN ======
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📌 Hướng dẫn',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Chọn loại báo cáo cần xuất\n'
                    '2. File Excel sẽ tự động được tạo và mở\n'
                    '3. File được lưu trong thư mục Download của thiết bị\n'
                    '4. Có thể mở bằng Microsoft Excel hoặc Google Sheets\n'
                    '5. Báo cáo tài chính có 4 sheet: Tổng quan, Thu chi theo lô, Chi tiết giao dịch, Phân bổ chi phí',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
    );
  }

  Widget _buildReportCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.grey,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }

  void _showFieldSelectionDialog(
    BuildContext context,
    FinanceProvider provider,
  ) {
    final reports = provider.generateProfitReport();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Chọn lô đất'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: reports.length,
              itemBuilder: (ctx, index) {
                final report = reports[index];
                return ListTile(
                  title: Text(report.fieldName),
                  subtitle: Text(
                    'Lợi nhuận: ${report.profit.toStringAsFixed(0)} VND',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await ReportService.exportFinanceByFieldReport(
                        provider,
                        report.fieldId,
                        report.fieldName,
                      );
                      _showSuccess(
                        context,
                        'Đã xuất báo cáo cho ${report.fieldName}!',
                      );
                    } catch (e) {
                      _showError(context, 'Lỗi: $e');
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
