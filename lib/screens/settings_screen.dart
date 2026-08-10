import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/cloud_sync_provider.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/task_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';
import '../providers/field_provider.dart';
import '../providers/production_season_provider.dart';
import '../providers/production_log_provider.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_cost_provider.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '☁️ Đồng bộ dữ liệu',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Đồng bộ tất cả dữ liệu lên Cloud để sử dụng trên nhiều thiết bị',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _buildSyncButton(context),
          const SizedBox(height: 32),

          const Divider(),
          const SizedBox(height: 16),

          const Text(
            '⚙️ Cài đặt khác',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            icon: Icons.language,
            title: 'Ngôn ngữ',
            subtitle: 'Tiếng Việt',
            onTap: () {
              // TODO: Thêm chọn ngôn ngữ
            },
          ),
          _buildSettingItem(
            icon: Icons.palette,
            title: 'Chủ đề',
            subtitle: 'Sáng',
            onTap: () {
              // TODO: Thêm chủ đề
            },
          ),
          _buildSettingItem(
            icon: Icons.notifications,
            title: 'Thông báo',
            subtitle: 'Bật',
            onTap: () {
              // TODO: Thêm cài đặt thông báo
            },
          ),
          const SizedBox(height: 16),

          const Divider(),
          const SizedBox(height: 16),

          _buildSettingItem(
            icon: Icons.logout,
            title: 'Đăng xuất',
            subtitle: 'Đăng xuất khỏi ứng dụng',
            color: Colors.red,
            onTap: () {
              _confirmLogout(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton(BuildContext context) {
    return Consumer<CloudSyncProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            ElevatedButton(
              onPressed: provider.isSyncing
                  ? null
                  : () async {
                      try {
                        // Lấy dữ liệu từ các provider
                        final warehouseProvider = context.read<WarehouseProvider>();
                        final machineProvider = context.read<MachineProvider>();
                        final employeeProvider = context.read<EmployeeProvider>();
                        final taskProvider = context.read<TaskProvider>();
                        final financeProvider = context.read<FinanceProvider>();
                        final fuelProvider = context.read<FuelProvider>();
                        final fieldProvider = context.read<FieldProvider>();
                        final seasonProvider = context.read<ProductionSeasonProvider>();
                        final logProvider = context.read<ProductionLogProvider>();
                        final harvestProvider = context.read<HarvestProvider>();
                        final costProvider = context.read<ProductionCostProvider>();

                        await seasonProvider.loadForFields(
                          fieldProvider.fields.map((field) => field.id),
                        );
                        final seasonIds = seasonProvider.allSeasons.map((season) => season.id);
                        await Future.wait([
                          logProvider.loadForSeasons(seasonIds),
                          harvestProvider.loadForSeasons(seasonIds),
                          costProvider.loadForSeasons(seasonIds),
                        ]);

                        final success = await provider.syncAllData(
                          warehouseItems: warehouseProvider.items,
                          machines: machineProvider.machines,
                          employees: employeeProvider.employees,
                          tasks: taskProvider.tasks,
                          financeRecords: financeProvider.records,
                          fuels: fuelProvider.fuels,
                          fields: fieldProvider.fields,
                          seasons: seasonProvider.allSeasons,
                          productionLogs: logProvider.allLogs,
                          harvestRecords: harvestProvider.allRecords,
                          productionCosts: costProvider.allRecords,
                        );

                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Đồng bộ dữ liệu thành công!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ Lỗi đồng bộ: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: provider.isSyncing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Đang đồng bộ...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          provider.isConnected
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          provider.isConnected ? 'Đồng bộ ngay' : 'Kết nối lại',
                        ),
                      ],
                    ),
            ),
            if (provider.lastSyncTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'Đồng bộ lần cuối: ${provider.lastSyncTime}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (!provider.isConnected) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ Không có kết nối Cloud',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.primaryColor),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Xác nhận đăng xuất'),
          content: const Text('Bạn có chắc muốn đăng xuất khỏi ứng dụng?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Đăng xuất'),
            ),
          ],
        );
      },
    );
  }
}
