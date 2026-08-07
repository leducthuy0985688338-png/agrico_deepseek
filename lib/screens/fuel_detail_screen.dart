import 'package:flutter/material.dart';
import '../models/fuel_model.dart';
import '../providers/fuel_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/field_provider.dart';

class FuelDetailScreen extends StatefulWidget {
  final FuelModel fuel;
  const FuelDetailScreen({super.key, required this.fuel});

  @override
  State<FuelDetailScreen> createState() => _FuelDetailScreenState();
}

class _FuelDetailScreenState extends State<FuelDetailScreen> {
  late FuelModel _currentFuel;
  final FuelProvider _fuelProvider = FuelProvider();
  final MachineProvider _machineProvider = MachineProvider();
  final FieldProvider _fieldProvider = FieldProvider();

  @override
  void initState() {
    super.initState();
    _currentFuel = widget.fuel;
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _fuelProvider.getTransactionsByFuel(_currentFuel.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentFuel.name),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin cơ bản
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentFuel.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _currentFuel.stock > 100
                                ? Colors.green
                                : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Tồn: ${_currentFuel.stock} ${_currentFuel.unit}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text('Đơn vị tính: ${_currentFuel.unit}'),
                    Text(
                      'Đơn giá: ${_currentFuel.unitPrice.toStringAsFixed(0)} VND/${_currentFuel.unit}',
                    ),
                    Text('Nhà cung cấp: ${_currentFuel.supplier}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Nút Nhập/Xuất
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _showImportDialog();
                    },
                    icon: const Icon(Icons.add_box),
                    label: const Text('Nhập kho'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _showExportDialog();
                    },
                    icon: const Icon(Icons.remove),
                    label: const Text('Xuất cho máy'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Lịch sử giao dịch
            const Text(
              'Lịch sử giao dịch',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              ...transactions.map((transaction) {
                return Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: transaction.type.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        transaction.type.icon,
                        color: transaction.type.color,
                      ),
                    ),
                    title: Text(
                      transaction.type.displayName,
                      style: TextStyle(
                        color: transaction.type.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${transaction.date.day}/${transaction.date.month}/${transaction.date.year} '
                          '${transaction.date.hour}:${transaction.date.minute.toString().padLeft(2, '0')}',
                        ),
                        if (transaction.machineName != null)
                          Text('Máy: ${transaction.machineName}'),
                        if (transaction.fieldName != null)
                          Text('Lô: ${transaction.fieldName}'),
                        if (transaction.operatorName != null)
                          Text('Người vận hành: ${transaction.operatorName}'),
                        if (transaction.note != null)
                          Text('Ghi chú: ${transaction.note}'),
                      ],
                    ),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${transaction.type == TransactionType.NHAP ? "+" : "-"}${transaction.quantity} ${_currentFuel.unit}',
                          style: TextStyle(
                            color: transaction.type.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (transaction.price != null)
                          Text(
                            '${(transaction.price! * transaction.quantity).toStringAsFixed(0)} VND',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // Hộp thoại Nhập kho
  void _showImportDialog() {
    final TextEditingController qtyCtrl = TextEditingController();
    final TextEditingController priceCtrl = TextEditingController(
      text: _currentFuel.unitPrice.toString(),
    );
    final TextEditingController noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('NHẬP KHO'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Loại: ${_currentFuel.name}'),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Số lượng (${_currentFuel.unit}) *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Đơn giá nhập *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text) ?? 0;
                final price = double.tryParse(priceCtrl.text) ?? 0;
                if (qty <= 0 || price <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập số lượng và đơn giá hợp lệ'),
                    ),
                  );
                  return;
                }

                _fuelProvider.importFuel(
                  _currentFuel.id,
                  qty,
                  price,
                  note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
                );

                setState(() {
                  _currentFuel = _fuelProvider.fuels.firstWhere(
                    (f) => f.id == _currentFuel.id,
                  );
                });

                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Đã nhập kho thành công!')),
                );
              },
              child: const Text('Nhập'),
            ),
          ],
        );
      },
    );
  }

  // Hộp thoại Xuất cho máy
  void _showExportDialog() {
    final TextEditingController qtyCtrl = TextEditingController();
    String? selectedMachineId;
    String? selectedFieldId;
    final TextEditingController operatorCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();

    final machines = _machineProvider.machines;
    final fields = _fieldProvider.fields;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('XUẤT CHO MÁY'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Loại: ${_currentFuel.name}'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Số lượng (${_currentFuel.unit}) *',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Chọn máy
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Chọn Máy *',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedMachineId,
                      items: machines.map((machine) {
                        return DropdownMenuItem(
                          value: machine.id,
                          child: Text('${machine.name} (${machine.type})'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          selectedMachineId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    // Chọn lô đất (tùy chọn)
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Lô đất làm việc (tùy chọn)',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedFieldId,
                      items: fields.map((field) {
                        return DropdownMenuItem(
                          value: field.id,
                          child: Text(field.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          selectedFieldId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: operatorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên người vận hành',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú',
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
                    final qty = double.tryParse(qtyCtrl.text) ?? 0;
                    if (qty <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Vui lòng nhập số lượng hợp lệ'),
                        ),
                      );
                      return;
                    }

                    if (selectedMachineId == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Vui lòng chọn máy')),
                      );
                      return;
                    }

                    try {
                      final machine = machines.firstWhere(
                        (m) => m.id == selectedMachineId,
                      );
                      final field = selectedFieldId != null
                          ? fields.firstWhere((f) => f.id == selectedFieldId)
                          : null;

                      _fuelProvider.exportFuelToMachine(
                        fuelId: _currentFuel.id,
                        quantity: qty,
                        machineId: machine.id,
                        machineName: machine.name,
                        fieldId: field?.id,
                        fieldName: field?.name,
                        operatorName: operatorCtrl.text.isNotEmpty
                            ? operatorCtrl.text
                            : null,
                        note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
                      );

                      setState(() {
                        _currentFuel = _fuelProvider.fuels.firstWhere(
                          (f) => f.id == _currentFuel.id,
                        );
                      });

                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Đã xuất nhiên liệu thành công!'),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  },
                  child: const Text('Xuất'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
