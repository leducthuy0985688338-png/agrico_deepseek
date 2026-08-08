import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.agriculture,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Agrico ERP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'admin@agrico.com',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.dashboard,
                  title: 'Tổng quan',
                  onTap: () {
                    Navigator.pop(context);
                    // Điều hướng đến Dashboard
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.farm,
                  title: 'Trang trại',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.map,
                  title: 'Lô đất',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.warehouse,
                  title: 'Kho',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.agriculture,
                  title: 'Máy móc',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.people,
                  title: 'Nhân sự',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.local_gas_station,
                  title: 'Nhiên liệu',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.money,
                  title: 'Tài chính',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  context,
                  icon: Icons.settings,
                  title: 'Cài đặt',
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.logout,
                  title: 'Đăng xuất',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.primaryColor, size: 24),
      title: Text(
        title,
        style: TextStyle(color: color ?? Colors.black87, fontSize: 15),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: AppTheme.primaryColor.withOpacity(0.1),
      splashColor: AppTheme.primaryColor.withOpacity(0.1),
    );
  }
}
