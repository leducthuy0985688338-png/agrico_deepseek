import 'package:flutter/material.dart';

class FuelModel {
  final String id;
  final String name; // Dầu Diesel, Xăng, Mỡ bôi trơn
  final String unit; // Lít, Kg
  double stock; // Tồn kho hiện tại
  final double unitPrice; // Đơn giá nhập
  final String supplier; // Nhà cung cấp
  List<FuelTransaction> transactions;

  FuelModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.unitPrice,
    required this.supplier,
    this.transactions = const [],
  });

  // Copy with method
  FuelModel copyWith({double? stock, List<FuelTransaction>? transactions}) {
    return FuelModel(
      id: id,
      name: name,
      unit: unit,
      stock: stock ?? this.stock,
      unitPrice: unitPrice,
      supplier: supplier,
      transactions: transactions ?? this.transactions,
    );
  }
}

// Model cho giao dịch nhiên liệu
class FuelTransaction {
  final String id;
  final String fuelId;
  final String fuelName;
  final DateTime date;
  final TransactionType type; // NHAP hoặc XUAT
  final double quantity;
  final double? price; // Giá tại thời điểm giao dịch
  final String? machineId; // Máy tiêu thụ (nếu xuất)
  final String? machineName;
  final String? fieldId; // Lô đất (nếu xuất)
  final String? fieldName;
  final String? operatorName;
  final String? note;

  FuelTransaction({
    required this.id,
    required this.fuelId,
    required this.fuelName,
    required this.date,
    required this.type,
    required this.quantity,
    this.price,
    this.machineId,
    this.machineName,
    this.fieldId,
    this.fieldName,
    this.operatorName,
    this.note,
  });
}

enum TransactionType { NHAP, XUAT }

extension TransactionTypeExtension on TransactionType {
  String get displayName {
    switch (this) {
      case TransactionType.NHAP:
        return 'Nhập';
      case TransactionType.XUAT:
        return 'Xuất';
    }
  }

  Color get color {
    switch (this) {
      case TransactionType.NHAP:
        return Colors.green;
      case TransactionType.XUAT:
        return Colors.orange;
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionType.NHAP:
        return Icons.add_box;
      case TransactionType.XUAT:
        return Icons.remove;
    }
  }
}
