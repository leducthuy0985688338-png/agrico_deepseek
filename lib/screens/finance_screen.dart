import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/finance_provider.dart';
import '../models/finance_model.dart';
import 'finance_detail_screen.dart';

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FinanceProvider>();

    final totalRevenue = provider.getTotalRevenue();
    final totalCost = provider.getTotalCost();
    final totalProfit = provider.getTotalProfit();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài chính'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              _showAddTransactionDialog(context, provider);
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ====== TỔNG QUAN TÀI CHÍNH ======
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Tổng thu',
                    '${totalRevenue.toStringAsFixed(0)} VND',
                    Icons.arrow_upward,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Tổng chi',
                    '${totalCost.toStringAsFixed(0)} VND',
                    Icons.arrow_downward,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: totalProfit >= 0
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      totalProfit >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: totalProfit >= 0 ? Colors.green : Colors.red,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lợi nhuận',
                          style: TextStyle(
                            color: totalProfit >= 0 ? Colors.green : Colors.red,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${totalProfit >= 0 ? "+" : ""}${totalProfit.toStringAsFixed(0)} VND',
                          style: TextStyle(
                            color: totalProfit >= 0 ? Colors.green : Colors.red,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ====== BÁO CÁO LỢI NHUẬN THEO LÔ ======
            const Text(
              'Lợi nhuận theo lô',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...provider.generateProfitReport().map((report) {
              return Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: report.profit >= 0
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      report.profit >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: report.profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(
                    report.fieldName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Thu: ${report.totalRevenue.toStringAsFixed(0)} VND\n'
                    'Chi: ${report.totalCost.toStringAsFixed(0)} VND',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${report.profit >= 0 ? "+" : ""}${report.profit.toStringAsFixed(0)} VND',
                        style: TextStyle(
                          color: report.profit >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tỷ suất: ${report.profitMargin.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FinanceDetailScreen(fieldId: report.fieldId),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
            const SizedBox(height: 16),

            // ====== NGÂN SÁCH THEO LÔ ======
            const Text(
              'Ngân sách theo lô',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...provider.budgets.map((budget) {
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.account_balance,
                    color: Colors.blue,
                  ),
                  title: Text(budget.fieldName),
                  subtitle: Text(
                    'Dự kiến: ${budget.estimatedBudget.toStringAsFixed(0)} VND\n'
                    'Đã chi: ${budget.totalSpent.toStringAsFixed(0)} VND',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${budget.remainingBudget.toStringAsFixed(0)} VND',
                        style: TextStyle(
                          color: budget.remainingBudget >= 0
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        budget.remainingBudget >= 0 ? 'Còn lại' : 'Vượt chi',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTransactionDialog(
    BuildContext context,
    FinanceProvider provider,
  ) {
    final TextEditingController fieldCtrl = TextEditingController();
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController categoryCtrl = TextEditingController();
    final TextEditingController descCtrl = TextEditingController();

    TransactionType selectedType = TransactionType.CHI;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('THÊM GIAO DỊCH'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Loại giao dịch
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<TransactionType>(
                            title: const Text('Chi'),
                            value: TransactionType.CHI,
                            groupValue: selectedType,
                            onChanged: (value) {
                              setStateDialog(() {
                                selectedType = value!;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<TransactionType>(
                            title: const Text('Thu'),
                            value: TransactionType.THU,
                            groupValue: selectedType,
                            onChanged: (value) {
                              setStateDialog(() {
                                selectedType = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: fieldCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mã lô đất (LO0001)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: categoryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục (Lương, Vật tư, Nhiên liệu,...)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền (VND)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(amountCtrl.text) ?? 0;
                    if (fieldCtrl.text.isEmpty ||
                        amount <= 0 ||
                        categoryCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Vui lòng điền đầy đủ thông tin'),
                        ),
                      );
                      return;
                    }

                    final newRecord = FinanceRecord(
                      id: 'F${DateTime.now().millisecondsSinceEpoch}',
                      fieldId: fieldCtrl.text,
                      fieldName: 'Lô ${fieldCtrl.text}',
                      date: DateTime.now(),
                      type: selectedType,
                      category: categoryCtrl.text,
                      amount: amount,
                      description: descCtrl.text.isNotEmpty
                          ? descCtrl.text
                          : null,
                    );

                    provider.addTransaction(newRecord);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Đã thêm giao dịch!')),
                    );
                  },
                  child: const Text('Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
