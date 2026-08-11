class WarehouseItem {
  final String id; // Mã hàng (PB0001)
  final String name; // Tên hàng hoá
  final String unit; // Đơn vị tính (Kg)
  final double importPrice; // Đơn giá nhập
  final String supplier; // Nhà cung cấp
  int stock; // Tồn kho (sẽ thay đổi)

  WarehouseItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.importPrice,
    required this.supplier,
    this.stock = 0,
  });

  factory WarehouseItem.fromMap(Map<String, dynamic> map) {
    return WarehouseItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      importPrice: (map['importPrice'] as num?)?.toDouble() ?? 0,
      supplier: map['supplier']?.toString() ?? '',
      stock: (map['stock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'importPrice': importPrice,
      'supplier': supplier,
      'stock': stock,
    };
  }
}
