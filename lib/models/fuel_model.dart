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

  factory FuelModel.fromMap(Map<String, dynamic> map) {
    return FuelModel(
      id: map['id'] as String,
      name: map['name'] as String,
      unit: map['unit'] as String,
      stock: (map['stock'] as num).toDouble(),
      unitPrice: (map['unitPrice'] as num).toDouble(),
      supplier: map['supplier'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'stock': stock,
      'unitPrice': unitPrice,
      'supplier': supplier,
    };
  }

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

class FuelTransaction {
  final String id;
  final String fuelId;
  final String fuelName;
  final DateTime date;
  final TransactionType type;
  final double quantity;
  final double? price;
  final String? machineId;
  final String? machineName;
  final String? fieldId;
  final String? fieldName;
  final String? seasonId;
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
    this.seasonId,
    this.operatorName,
    this.note,
  });

  factory FuelTransaction.fromMap(Map<String, dynamic> map) {
    return FuelTransaction(
      id: map['id'] as String,
      fuelId: map['fuelId'] as String,
      fuelName: map['fuelName'] as String,
      date: DateTime.parse(map['date'] as String),
      type: TransactionType.values[(map['type'] as num).toInt()],
      quantity: (map['quantity'] as num).toDouble(),
      price: (map['price'] as num?)?.toDouble(),
      machineId: map['machineId'] as String?,
      machineName: map['machineName'] as String?,
      fieldId: map['fieldId'] as String?,
      fieldName: map['fieldName'] as String?,
      seasonId: map['seasonId'] as String?,
      operatorName: map['operatorName'] as String?,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fuelId': fuelId,
      'fuelName': fuelName,
      'date': date.toIso8601String(),
      'type': type.index,
      'quantity': quantity,
      'price': price,
      'machineId': machineId,
      'machineName': machineName,
      'fieldId': fieldId,
      'fieldName': fieldName,
      'seasonId': seasonId,
      'operatorName': operatorName,
      'note': note,
    };
  }
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
