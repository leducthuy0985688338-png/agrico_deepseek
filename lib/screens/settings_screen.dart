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
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt'), backgroundColor: AppTheme.primaryColor),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(leading: const Icon(Icons.cloud_sync), title: const Text('Đồng bộ dữ liệu'), onTap: () {}),
        ListTile(leading: const Icon(Icons.inventory_2), title: const Text('Kho'), onTap: () {}),
        ListTile(leading: const Icon(Icons.agriculture), title: const Text('Máy móc'), onTap: () {}),
        ListTile(leading: const Icon(Icons.people), title: const Text('Nhân sự'), onTap: () {}),
        ListTile(leading: const Icon(Icons.account_balance_wallet), title: const Text('Tài chính'), onTap: () {}),
        const Divider(),
        ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Đăng xuất'), onTap: () => _logout(context)),
      ]),
    );
  }

  void _logout(BuildContext context) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Đăng xuất'), content: const Text('Bạn có chắc muốn đăng xuất khỏi ứng dụng?'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
      ElevatedButton(onPressed: () { Navigator.pop(ctx); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Đăng xuất')),
    ]));
  }
}
