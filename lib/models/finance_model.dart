class FinanceRecord {
  final String id;
  final String fieldId; // Lô đất liên quan (nếu có)
  final String fieldName;
  final DateTime date;
  final TransactionType type; // THU hoặc CHI
  final String
  category; // Phân loại: Lương, Vật tư, Nhiên liệu, Bảo trì, Thu hoạch,...
  final double amount;
  final String? description;
  final String? machineId; // Máy liên quan (nếu có)
  final String? machineName;

  FinanceRecord({
    required this.id,
    required this.fieldId,
    required this.fieldName,
    required this.date,
    required this.type,
    required this.category,
    required this.amount,
    this.description,
    this.machineId,
    this.machineName,
  });

  factory FinanceRecord.fromMap(Map<String, dynamic> map) {
    return FinanceRecord(
      id: map['id'] as String,
      fieldId: map['fieldId'] as String,
      fieldName: map['fieldName'] as String,
      date: DateTime.parse(map['date'] as String),
      type: TransactionType.values[(map['type'] as num).toInt()],
      category: map['category'] as String,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String?,
      machineId: map['machineId'] as String?,
      machineName: map['machineName'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fieldId': fieldId,
      'fieldName': fieldName,
      'date': date.toIso8601String(),
      'type': type.index,
      'category': category,
      'amount': amount,
      'description': description,
      'machineId': machineId,
      'machineName': machineName,
    };
  }
}

enum TransactionType { THU, CHI }

extension TransactionTypeExtension on TransactionType {
  String get displayName {
    switch (this) {
      case TransactionType.THU:
        return 'Thu';
      case TransactionType.CHI:
        return 'Chi';
    }
  }

  String get sign {
    switch (this) {
      case TransactionType.THU:
        return '+';
      case TransactionType.CHI:
        return '-';
    }
  }
}

// Model cho Ngân sách theo lô
class FieldBudget {
  final String fieldId;
  final String fieldName;
  final double estimatedBudget; // Ngân sách dự kiến
  double totalSpent; // Đã chi
  double totalRevenue; // Đã thu
  double get profit => totalRevenue - totalSpent;
  double get remainingBudget => estimatedBudget - totalSpent;

  FieldBudget({
    required this.fieldId,
    required this.fieldName,
    required this.estimatedBudget,
    this.totalSpent = 0,
    this.totalRevenue = 0,
  });
}

// Model cho Báo cáo lợi nhuận
class ProfitReport {
  final String fieldId;
  final String fieldName;
  final double totalCost; // Tổng chi phí
  final double totalRevenue; // Tổng doanh thu
  final double profit; // Lợi nhuận
  final double profitMargin; // Tỷ suất lợi nhuận (%)

  ProfitReport({
    required this.fieldId,
    required this.fieldName,
    required this.totalCost,
    required this.totalRevenue,
    required this.profit,
    required this.profitMargin,
  });
}
