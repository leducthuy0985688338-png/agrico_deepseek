import 'package:flutter/material.dart';
import '../providers/finance_provider.dart';
import '../models/finance_model.dart';

class FinanceDetailScreen extends StatelessWidget {
  final String fieldId;
  const FinanceDetailScreen({super.key, required this.fieldId});

  @override
  Widget build(BuildContext context) {
    final provider = FinanceProvider();
    final transactions = provider.getTransactionsByField(fieldId);

    final totalRevenue = provider.getTotalRevenueByField(fieldId);
    final totalCost = provider.getTotalCostByField(fieldId);
    final profit = totalRevenue - totalCost;

    return Scaffold(
      appBar: AppBar(
        title: Text('Chi tiết tài chính - Lô ${fieldId}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ====== TỔNG QUAN ======
            Row(
              children: [
                Expanded(
                  child: _buildDetailCard(
                    'Tổng thu',
                    '${totalRevenue.toStringAsFixed(0)} VND',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDetailCard(
                    'Tổng chi',
                    '${totalCost.toStringAsFixed(0)} VND',
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: profit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      profit >= 0 ? Icons.trending_up : Icons.trending_down,
                      color: profit >= 0 ? Colors.green : Colors.red,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lợi nhuận',
                          style: TextStyle(
                            color: profit >= 0 ? Colors.green : Colors.red,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${profit >= 0 ? "+" : ""}${profit.toStringAsFixed(0)} VND',
                          style: TextStyle(
                            color: profit >= 0 ? Colors.green : Colors.red,
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

            // ====== DANH SÁCH GIAO DỊCH ======
            const Text(
              'Lịch sử giao dịch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (transactions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Chưa có giao dịch nào')),
                ),
              )
            else
              ...transactions.map((record) {
                return Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: record.type == TransactionType.THU
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        record.type == TransactionType.THU
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        color: record.type == TransactionType.THU
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          record.type.displayName,
                          style: TextStyle(
                            color: record.type == TransactionType.THU
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          record.category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${record.date.day}/${record.date.month}/${record.date.year}',
                        ),
                        if (record.description != null)
                          Text(record.description!),
                        if (record.machineName != null)
                          Text('Máy: ${record.machineName}'),
                      ],
                    ),
                    trailing: Text(
                      '${record.type == TransactionType.THU ? "+" : "-"}${record.amount.toStringAsFixed(0)} VND',
                      style: TextStyle(
                        color: record.type == TransactionType.THU
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
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
}
