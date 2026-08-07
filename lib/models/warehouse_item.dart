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

  // Chuyển đổi từ Map (khi lưu xuống database)
  factory WarehouseItem.fromMap(Map<String, dynamic> map) {
    return WarehouseItem(
      id: map['id'],
      name: map['name'],
      unit: map['unit'],
      importPrice: map['importPrice'],
      supplier: map['supplier'],
      stock: map['stock'],
    );
  }

  // Chuyển đổi sang Map
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
