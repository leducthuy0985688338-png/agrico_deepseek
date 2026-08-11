import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          const SizedBox(height: 12),
          _buildRestoreFieldButton(context),
          const SizedBox(height: 8),
          const Text(
            'Khôi phục danh mục lô đất và toàn bộ ranh giới GPS từ Cloud.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _buildRestoreSeasonButton(context),
          const SizedBox(height: 8),
          const Text(
            'Khôi phục mùa vụ theo lô đất trước khi tải nhật ký sản xuất.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _buildRestoreProductionLogButton(context),
          const SizedBox(height: 8),
          const Text(
            'Khôi phục nhật ký sản xuất theo đúng lô đất và mùa vụ.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _buildRestoreFuelButton(context),
          const SizedBox(height: 8),
          const Text(
            'Khôi phục danh mục và sổ nhập/xuất nhiên liệu từ Cloud.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _buildRestoreFinanceButton(context),
          const SizedBox(height: 8),
          const Text(
            'Khôi phục toàn bộ sổ Thu/Chi từ Cloud và tính lại ngân sách.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
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
              onPressed: provider.isBusy
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
                          fuelTransactions: fuelProvider.allTransactions,
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

  Widget _buildRestoreFieldButton(BuildContext context) {
    return Consumer<CloudSyncProvider>(
      builder: (context, provider, child) {
        return OutlinedButton(
          onPressed: provider.isBusy
              ? null
              : () => _confirmFieldRestore(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: provider.isRestoringFields
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Đang khôi phục lô đất...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map),
                    SizedBox(width: 8),
                    Text('Khôi phục lô đất từ Cloud'),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _confirmFieldRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục dữ liệu lô đất?'),
        content: const Text(
          'Danh mục lô đất và ranh giới GPS hiện tại sẽ được thay bằng bản '
          'trên Cloud. Hãy đồng bộ dữ liệu mới nhất trước nếu cần giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cloudProvider = context.read<CloudSyncProvider>();
    final fieldProvider = context.read<FieldProvider>();

    try {
      final fields = await cloudProvider.restoreFieldData();
      if (!context.mounted) return;

      if (fields.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud chưa có dữ liệu lô đất.')),
        );
        return;
      }

      await fieldProvider.restoreFromCloud(fields: fields);
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã khôi phục ${fields.length} lô đất và ranh giới GPS.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi khôi phục lô đất: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRestoreSeasonButton(BuildContext context) {
    return Consumer<CloudSyncProvider>(
      builder: (context, provider, child) {
        return OutlinedButton(
          onPressed: provider.isBusy
              ? null
              : () => _confirmSeasonRestore(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: provider.isRestoringSeasons
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Đang khôi phục mùa vụ...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.agriculture),
                    SizedBox(width: 8),
                    Text('Khôi phục mùa vụ từ Cloud'),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _confirmSeasonRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục dữ liệu mùa vụ?'),
        content: const Text(
          'Toàn bộ mùa vụ hiện tại sẽ được thay bằng bản trên Cloud. '
          'Hãy khôi phục lô đất trước để giữ đúng liên kết dữ liệu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cloudProvider = context.read<CloudSyncProvider>();
    final fieldProvider = context.read<FieldProvider>();
    final seasonProvider = context.read<ProductionSeasonProvider>();

    try {
      final seasons = await cloudProvider.restoreSeasonData();
      if (!context.mounted) return;

      if (seasons.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud chưa có dữ liệu mùa vụ.')),
        );
        return;
      }

      final fieldIds = fieldProvider.fields.map((field) => field.id).toSet();
      final validSeasons = seasons
          .where((season) => fieldIds.contains(season.fieldId))
          .toList(growable: false);
      final skippedCount = seasons.length - validSeasons.length;

      if (validSeasons.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không có mùa vụ nào khớp với lô đất hiện tại. '
              'Hãy khôi phục lô đất trước.',
            ),
          ),
        );
        return;
      }

      await seasonProvider.restoreFromCloud(seasons: validSeasons);
      if (!context.mounted) return;

      final skippedMessage = skippedCount == 0
          ? ''
          : ' Bỏ qua $skippedCount mùa vụ không còn lô đất.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã khôi phục ${validSeasons.length} mùa vụ.'
            '$skippedMessage',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi khôi phục mùa vụ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRestoreProductionLogButton(BuildContext context) {
    return Consumer<CloudSyncProvider>(
      builder: (context, provider, child) {
        return OutlinedButton(
          onPressed: provider.isBusy
              ? null
              : () => _confirmProductionLogRestore(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: provider.isRestoringProductionLogs
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Đang khôi phục nhật ký sản xuất...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu_book),
                    SizedBox(width: 8),
                    Text('Khôi phục nhật ký sản xuất từ Cloud'),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _confirmProductionLogRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục nhật ký sản xuất?'),
        content: const Text(
          'Toàn bộ nhật ký sản xuất hiện tại sẽ được thay bằng bản trên '
          'Cloud. Hãy khôi phục lô đất và mùa vụ trước để giữ đúng liên kết.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cloudProvider = context.read<CloudSyncProvider>();
    final fieldProvider = context.read<FieldProvider>();
    final seasonProvider = context.read<ProductionSeasonProvider>();
    final logProvider = context.read<ProductionLogProvider>();

    try {
      final logs = await cloudProvider.restoreProductionLogData();
      if (!context.mounted) return;

      if (logs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloud chưa có dữ liệu nhật ký sản xuất.'),
          ),
        );
        return;
      }

      final fieldIds = fieldProvider.fields.map((field) => field.id).toSet();
      final seasonsById = {
        for (final season in seasonProvider.allSeasons) season.id: season,
      };
      final validLogs = logs.where((log) {
        final season = seasonsById[log.seasonId];
        return season != null &&
            season.fieldId == log.fieldId &&
            fieldIds.contains(log.fieldId);
      }).toList(growable: false);
      final skippedCount = logs.length - validLogs.length;

      if (validLogs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không có nhật ký nào khớp với lô đất và mùa vụ hiện tại. '
              'Hãy khôi phục lô đất, rồi khôi phục mùa vụ trước.',
            ),
          ),
        );
        return;
      }

      await logProvider.restoreFromCloud(logs: validLogs);
      if (!context.mounted) return;

      final skippedMessage = skippedCount == 0
          ? ''
          : ' Bỏ qua $skippedCount nhật ký mất liên kết.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã khôi phục ${validLogs.length} nhật ký sản xuất.'
            '$skippedMessage',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi khôi phục nhật ký sản xuất: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRestoreFuelButton(BuildContext context) {
    return Consumer<CloudSyncProvider>(
      builder: (context, provider, child) {
        return OutlinedButton(
          onPressed: provider.isBusy
              ? null
              : () => _confirmFuelRestore(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: provider.isRestoringFuel
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Đang khôi phục nhiên liệu...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_download),
                    SizedBox(width: 8),
                    Text('Khôi phục nhiên liệu từ Cloud'),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _confirmFuelRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục dữ liệu nhiên liệu?'),
        content: const Text(
          'Danh mục nhiên liệu và sổ nhập/xuất hiện tại sẽ được thay bằng '
          'bản trên Cloud. Hãy đồng bộ dữ liệu mới nhất trước nếu cần giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cloudProvider = context.read<CloudSyncProvider>();
    final fuelProvider = context.read<FuelProvider>();

    try {
      final data = await cloudProvider.restoreFuelData();
      if (!context.mounted) return;

      if (data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud chưa có dữ liệu nhiên liệu.')),
        );
        return;
      }

      fuelProvider.restoreFromCloud(
        fuels: data.fuels,
        transactions: data.transactions,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã khôi phục ${data.fuels.length} loại nhiên liệu và '
            '${data.transactions.length} phiếu.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi khôi phục nhiên liệu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRestoreFinanceButton(BuildContext context) {
    return Consumer<CloudSyncProvider>(
      builder: (context, provider, child) {
        return OutlinedButton(
          onPressed: provider.isBusy
              ? null
              : () => _confirmFinanceRestore(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: provider.isRestoringFinance
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Đang khôi phục tài chính...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.account_balance_wallet),
                    SizedBox(width: 8),
                    Text('Khôi phục tài chính từ Cloud'),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _confirmFinanceRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục dữ liệu tài chính?'),
        content: const Text(
          'Toàn bộ sổ Thu/Chi hiện tại sẽ được thay bằng bản trên Cloud. '
          'Hãy đồng bộ dữ liệu mới nhất trước nếu cần giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cloudProvider = context.read<CloudSyncProvider>();
    final financeProvider = context.read<FinanceProvider>();

    try {
      final records = await cloudProvider.restoreFinanceData();
      if (!context.mounted) return;

      if (records.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud chưa có dữ liệu tài chính.')),
        );
        return;
      }

      financeProvider.restoreFromCloud(records: records);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Đã khôi phục ${records.length} giao dịch tài chính.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi khôi phục tài chính: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (route) => false);
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
