import 'package:flutter/material.dart';
import 'screens/warehouse_screen.dart';
import 'screens/field_list_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/employee_list_screen.dart';
import 'screens/fuel_screen.dart';
import 'screens/report_screen.dart';

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
    ReportScreen(), // 7: Báo cáo
    SettingsPage(), // 8: Cài đặt
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
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Báo cáo'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
    );
  }
}

// ---------- TRANG TỔNG QUAN ----------
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        children: const [
          Card(
            child: Center(
              child: Text('Lô đất: 2', style: TextStyle(fontSize: 20)),
            ),
          ),
          Card(
            child: Center(
              child: Text('Máy móc: 4', style: TextStyle(fontSize: 20)),
            ),
          ),
          Card(
            child: Center(
              child: Text('Nhân viên: 5', style: TextStyle(fontSize: 20)),
            ),
          ),
          Card(
            child: Center(
              child: Text('Doanh thu: 1.2 tỷ', style: TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- TRANG TRANG TRẠI ----------
class FarmPage extends StatelessWidget {
  const FarmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Danh sách Trang trại (sẽ thêm sau)',
        style: TextStyle(fontSize: 18),
      ),
    );
  }
}

// ---------- TRANG CÀI ĐẶT ----------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Cài đặt ngôn ngữ, đăng xuất (sẽ thêm sau)',
        style: TextStyle(fontSize: 18),
      ),
    );
  }
}
