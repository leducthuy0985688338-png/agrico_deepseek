import 'package:flutter/material.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../services/report_service.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Khởi tạo các provider
    final warehouseProvider = WarehouseProvider();
    final machineProvider = MachineProvider();
    final employeeProvider = EmployeeProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tiêu đề
          const Text(
            'Xuất báo cáo Excel',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn loại báo cáo bạn muốn xuất',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Các nút báo cáo
          _buildReportCard(
            context,
            icon: Icons.inventory,
            title: 'Báo cáo Tồn kho',
            subtitle: 'Xuất danh sách vật tư trong kho',
            color: Colors.blue,
            onTap: () async {
              try {
                await ReportService.exportWarehouseReport(warehouseProvider);
                _showSuccess(context, 'Báo cáo tồn kho đã được xuất!');
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
                _showSuccess(context, 'Báo cáo máy móc đã được xuất!');
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
                _showSuccess(context, 'Báo cáo nhân sự đã được xuất!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          _buildReportCard(
            context,
            icon: Icons.summarize,
            title: 'Báo cáo Tổng hợp',
            subtitle: 'Xuất báo cáo tổng hợp tất cả dữ liệu',
            color: Colors.green,
            onTap: () async {
              try {
                await ReportService.exportSummaryReport(
                  warehouseProvider,
                  machineProvider,
                  employeeProvider,
                );
                _showSuccess(context, 'Báo cáo tổng hợp đã được xuất!');
              } catch (e) {
                _showError(context, 'Lỗi: $e');
              }
            },
          ),

          const SizedBox(height: 24),

          // Hướng dẫn
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
                    '4. Có thể mở bằng Microsoft Excel hoặc Google Sheets',
                  ),
                ],
              ),
            ),
          ),
        ],
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
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 32),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
        onTap: onTap,
      ),
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
