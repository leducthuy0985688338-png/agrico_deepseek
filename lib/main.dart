import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import 'core/localization/app_locale_controller.dart';
import 'core/localization/app_localizations.dart';
import 'core/backup/local_restore_activation.dart';
import 'theme/app_theme.dart';
import 'services/cloud_service.dart';
import 'app_v2/agrico_v2_composition.dart';

// ====== IMPORT CÁC MÀN HÌNH ======
import 'screens/warehouse_screen.dart';
import 'screens/field_list_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/employee_list_screen.dart';
import 'screens/fuel_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/task_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';

// ====== IMPORT PROVIDER ======
import 'providers/dashboard_provider.dart';
import 'providers/field_provider.dart';
import 'providers/cloud_sync_provider.dart';
import 'providers/warehouse_provider.dart';
import 'providers/machine_provider.dart';
import 'providers/employee_provider.dart';
import 'providers/task_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/fuel_provider.dart';
import 'providers/production_season_provider.dart';
import 'providers/production_log_provider.dart';
import 'providers/harvest_provider.dart';
import 'providers/production_cost_provider.dart';

// ====== ĐIỂM KHỞI ĐẦU ======
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyPendingRestore();
  await CloudService.initialize();
  runApp(const MyApp());
}

// ====== APP CHÍNH ======
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.homeOverride});

  final Widget? homeOverride;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppLocaleController()),
        ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
        ChangeNotifierProvider.value(value: FieldProvider()),
        ChangeNotifierProvider(create: (_) => WarehouseProvider()),
        ChangeNotifierProvider(create: (_) => MachineProvider()),
        ChangeNotifierProvider(create: (_) => EmployeeProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
        ChangeNotifierProvider(create: (_) => FuelProvider()),
        ChangeNotifierProvider(create: (_) => ProductionSeasonProvider()),
        ChangeNotifierProvider(create: (_) => ProductionLogProvider()),
        ChangeNotifierProvider(create: (_) => HarvestProvider()),
        ChangeNotifierProvider(create: (_) => ProductionCostProvider()),
        ProxyProvider6<
          FieldProvider,
          WarehouseProvider,
          MachineProvider,
          EmployeeProvider,
          FinanceProvider,
          FuelProvider,
          DashboardProvider
        >(
          update:
              (
                _,
                fieldProvider,
                warehouseProvider,
                machineProvider,
                employeeProvider,
                financeProvider,
                fuelProvider,
                __,
              ) => DashboardProvider(
                fieldProvider: fieldProvider,
                warehouseProvider: warehouseProvider,
                machineProvider: machineProvider,
                employeeProvider: employeeProvider,
                financeProvider: financeProvider,
                fuelProvider: fuelProvider,
              ),
        ),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          onGenerateTitle: (context) => context.l10n.text('app.name'),
          // Preserve the legacy Vietnamese default. A persisted user preference
          // will replace this initial value when settings persistence is migrated.
          locale: context.watch<AppLocaleController>().locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.lightTheme,
          home: homeOverride ?? const LoginScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

// ============================================================
// ====== MÀN HÌNH ĐĂNG NHẬP ======
// ============================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryColor.withOpacity(0.1), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                TweenAnimationBuilder(
                  duration: const Duration(milliseconds: 800),
                  tween: Tween<double>(begin: 0, end: 1),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.agriculture,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  context.l10n.text('app.name'),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                Text(
                  context.l10n.text('app.tagline'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('auth.username'),
                    prefixIcon: const Icon(
                      Icons.person,
                      color: AppTheme.primaryColor,
                    ),
                    hintText: 'admin@agrico.com',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('auth.password'),
                    prefixIcon: const Icon(
                      Icons.lock,
                      color: AppTheme.primaryColor,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    hintText: '••••••••',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: Text(
                      context.l10n.text('auth.forgotPassword'),
                      style: const TextStyle(color: AppTheme.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Nút đăng nhập
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _isLoading = true);
                      Future.delayed(const Duration(seconds: 1), () {
                        setState(() => _isLoading = false);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AgricoV2Root(
                              userId: emailController.text.trim(),
                            ),
                          ),
                        );
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            context.l10n.text('auth.signIn'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.l10n.text('auth.demoHint'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ====== MÀN HÌNH CHÍNH (DASHBOARD) ======
// ============================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    HomePage(), // 0: Tổng quan
    FarmPage(), // 1: Trang trại
    FieldListScreen(), // 2: Lô đất
    WarehouseScreen(), // 3: Kho
    MachineListScreen(), // 4: Máy móc
    EmployeeListScreen(), // 5: Nhân sự
    FuelScreen(), // 6: Nhiên liệu
    FinanceScreen(), // 7: Tài chính
    TaskScreen(), // 8: Lịch công việc
    AiChatScreen(), // 9: AI
    ReportScreen(), // 10: Báo cáo
    SettingsPage(), // 11: Cài đặt
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.agriculture,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Agrico ERP',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            child: Text(
              'A',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.agriculture),
            label: 'Trang trại',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Lô đất'),
          BottomNavigationBarItem(icon: Icon(Icons.warehouse), label: 'Kho'),
          BottomNavigationBarItem(
            icon: Icon(Icons.agriculture),
            label: 'Máy móc',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Nhân sự'),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_gas_station),
            label: 'Nhiên liệu',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.money), label: 'Tài chính'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Lịch việc',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: 'AI'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Báo cáo'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
    );
  }
}

// ============================================================
// ====== TRANG TỔNG QUAN (DASHBOARD) ======
// ============================================================
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final monthlyData = provider.getMonthlyFinanceData();
    final costData = provider.getCostDistribution();
    final machineData = provider.getMachineStatusData();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header chào mừng
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.waving_hand, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chào buổi sáng! 👋',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Hôm nay là ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4 thẻ thống kê
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Tổng lô đất',
                  provider.totalFields.toString(),
                  Icons.map,
                  Colors.blue,
                  '${provider.totalFields} lô',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Máy móc',
                  provider.totalMachines.toString(),
                  Icons.agriculture,
                  Colors.orange,
                  '${provider.totalMachines} máy',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Nhân sự',
                  provider.totalEmployees.toString(),
                  Icons.people,
                  Colors.purple,
                  '${provider.totalEmployees} người',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Lợi nhuận',
                  '${provider.totalProfit >= 0 ? "+" : ""}${provider.totalProfit ~/ 1000000}tr',
                  Icons.trending_up,
                  provider.totalProfit >= 0 ? Colors.green : Colors.red,
                  provider.totalProfit >= 0 ? '📈 Tăng' : '📉 Giảm',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Biểu đồ cột Thu - Chi
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📈 Thu - Chi 6 tháng gần đây',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _getMaxY(monthlyData),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final item = monthlyData[groupIndex];
                              final value = rod.toY;
                              final label = rodIndex == 0 ? 'Thu' : 'Chi';
                              return BarTooltipItem(
                                '${item['month']}\n$label: ${value.toStringAsFixed(1)}tr',
                                const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < monthlyData.length) {
                                  return Text(
                                    monthlyData[index]['month'] ?? '',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        groupsSpace: 20,
                        barGroups: _getBarGroups(monthlyData),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem('Thu', Colors.green),
                      const SizedBox(width: 20),
                      _buildLegendItem('Chi', Colors.red),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2 biểu đồ tròn
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💰 Phân bổ chi phí',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 140,
                          child: PieChart(
                            PieChartData(
                              sections: _getPieSections(costData, _costColors),
                              sectionsSpace: 2,
                              centerSpaceRadius: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildPieLegend(costData, _costColors),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🚜 Tình trạng máy móc',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 140,
                          child: PieChart(
                            PieChartData(
                              sections: _getPieSections(
                                machineData,
                                _machineColors,
                              ),
                              sectionsSpace: 2,
                              centerSpaceRadius: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildPieLegend(machineData, _machineColors),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Thống kê nhanh
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📋 Thống kê nhanh',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          'Tổng thu',
                          '${provider.totalRevenue ~/ 1000000}tr',
                          Icons.arrow_upward,
                          Colors.green,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStat(
                          'Tổng chi',
                          '${provider.totalCost ~/ 1000000}tr',
                          Icons.arrow_downward,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          'Tồn kho',
                          provider.totalInventoryStock.toStringAsFixed(0),
                          Icons.inventory,
                          Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStat(
                          'Nhiên liệu',
                          provider.totalFuelStock.toStringAsFixed(0),
                          Icons.local_gas_station,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cảnh báo
          if (provider.totalProfit < 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Cảnh báo: Lợi nhuận đang âm! Cần kiểm tra lại chi phí.',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ====== HÀM HỖ TRỢ ======
  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  List<BarChartGroupData> _getBarGroups(List<Map<String, dynamic>> data) {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (item['revenue'] ?? 0).toDouble(),
              color: Colors.green,
              width: 10,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
            BarChartRodData(
              toY: (item['cost'] ?? 0).toDouble(),
              color: Colors.red,
              width: 10,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  double _getMaxY(List<Map<String, dynamic>> data) {
    double max = 0;
    for (var item in data) {
      final revenue = item['revenue'] ?? 0;
      final cost = item['cost'] ?? 0;
      if (revenue > max) max = revenue;
      if (cost > max) max = cost;
    }
    return max + 5;
  }

  static const List<Color> _costColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
  ];

  static const List<Color> _machineColors = [
    Colors.green,
    Colors.orange,
    Colors.red,
  ];

  List<PieChartSectionData> _getPieSections(
    List<Map<String, dynamic>> data,
    List<Color> colors,
  ) {
    final total = data.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0));
    if (total == 0) return [];
    return data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final percentage = (item['amount'] / total * 100);
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: item['amount'],
        title: '${percentage.toStringAsFixed(0)}%',
        radius: 40,
        titleStyle: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<Widget> _buildPieLegend(
    List<Map<String, dynamic>> data,
    List<Color> colors,
  ) {
    final widgets = <Widget>[];
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors[i % colors.length],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${item['category']} (${(item['amount'] ?? 0).toStringAsFixed(1)})',
                  style: const TextStyle(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}

// ============================================================
// ====== TRANG TRANG TRẠI ======
// ============================================================
class FarmPage extends StatelessWidget {
  const FarmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.green.shade50, Colors.white],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.agriculture, size: 80, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Danh sách Trang trại',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Tính năng đang phát triển',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
