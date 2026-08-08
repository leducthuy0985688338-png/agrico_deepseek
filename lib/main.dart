import 'package:flutter/material.dart';
import 'screens/warehouse_screen.dart';
import 'screens/field_list_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/employee_list_screen.dart';
import 'screens/fuel_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/report_screen.dart';
import 'providers/dashboard_provider.dart';
import 'widgets/stat_card_widget.dart';
import 'widgets/bar_chart_widget.dart';
import 'widgets/pie_chart_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agrico ERP',
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}

// ---------- MÀN HÌNH ĐĂNG NHẬP ----------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.agriculture, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            const Text(
              'AGRICO ERP',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email / Tên đăng nhập',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DashboardScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('ĐĂNG NHẬP', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('(Nhấn nút để vào Demo, không cần mật khẩu)'),
          ],
        ),
      ),
    );
  }
}

// ---------- MÀN HÌNH CHÍNH (DASHBOARD) ----------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // Danh sách các trang theo đúng thứ tự
  static const List<Widget> _pages = [
    HomePage(), // 0: Tổng quan
    FarmPage(), // 1: Trang trại
    FieldListScreen(), // 2: Lô đất
    WarehouseScreen(), // 3: Kho
    MachineListScreen(), // 4: Máy móc
    EmployeeListScreen(), // 5: Nhân sự
    FuelScreen(), // 6: Nhiên liệu
    FinanceScreen(), // 7: Tài chính
    AiChatScreen(), // 8: Trợ lý AI
    ReportScreen(), // 9: Báo cáo
    SettingsPage(), // 10: Cài đặt
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agrico ERP'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
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
            icon: Icon(Icons.smart_toy),
            label: 'Trợ lý AI',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Báo cáo'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
    );
  }
}

/// ---------- TRANG TỔNG QUAN (DASHBOARD) ----------
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = DashboardProvider();
    final monthlyData = provider.getMonthlyFinanceData();
    final costData = provider.getCostDistribution();
    final machineData = provider.getMachineStatusData();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ====== TIÊU ĐỀ ======
          const Text(
            '📊 Tổng quan trang trại',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // ====== 4 THẺ THỐNG KÊ ======
          Row(
            children: [
              Expanded(
                child: StatCardWidget(
                  title: 'Tổng lô đất',
                  value: provider.totalFields.toString(),
                  icon: Icons.map,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCardWidget(
                  title: 'Máy móc',
                  value: provider.totalMachines.toString(),
                  icon: Icons.agriculture,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatCardWidget(
                  title: 'Nhân sự',
                  value: provider.totalEmployees.toString(),
                  icon: Icons.people,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCardWidget(
                  title: 'Lợi nhuận',
                  value:
                      '${provider.totalProfit >= 0 ? "+" : ""}${provider.totalProfit ~/ 1000000}tr',
                  icon: Icons.trending_up,
                  color: provider.totalProfit >= 0 ? Colors.green : Colors.red,
                  subtitle: provider.totalProfit >= 0 ? '📈 Tăng' : '📉 Giảm',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ====== BIỂU ĐỒ THU CHI ======
          BarChartWidget(
            data: monthlyData,
            title: '📈 Thu - Chi 6 tháng gần đây',
            barColor: Colors.green,
          ),
          const SizedBox(height: 16),

          // ====== BIỂU ĐỒ PHÂN BỔ CHI PHÍ + TRẠNG THÁI MÁY ======
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PieChartWidget(
                  data: costData,
                  title: '💰 Phân bổ chi phí',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PieChartWidget(
                  data: machineData.map((item) {
                    return {
                      'category': item['status'],
                      'amount': item['count'],
                    };
                  }).toList(),
                  title: '🚜 Tình trạng máy móc',
                  colors: [Colors.green, Colors.orange, Colors.red],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ====== THỐNG KÊ NHANH ======
          Card(
            elevation: 2,
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
                          '${_getTotalStock(provider)}',
                          Icons.inventory,
                          Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStat(
                          'Nhiên liệu',
                          '${_getTotalFuel(provider)} L',
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
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  String _getTotalStock(DashboardProvider provider) {
    // Lấy tổng số lượng tồn kho
    int total = 0;
    // Cần lấy từ WarehouseProvider, tạm thời hardcode
    return '200+';
  }

  String _getTotalFuel(DashboardProvider provider) {
    // Lấy tổng nhiên liệu
    // Tạm thời hardcode
    return '620';
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

// ============================================================
// ====== TRANG CÀI ĐẶT ======
// ============================================================
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
            Icon(Icons.settings, size: 80, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Cài đặt',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Ngôn ngữ, đăng xuất, ...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
