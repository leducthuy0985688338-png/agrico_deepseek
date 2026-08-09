import 'package:flutter/material.dart';

import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../providers/production_cost_provider.dart';
import 'production_cost_dashboard_screen.dart';

class ProductionCostScreen extends StatefulWidget {
  final ProductionSeasonModel season;
  const ProductionCostScreen({super.key, required this.season});

  @override
  State<ProductionCostScreen> createState() => _ProductionCostScreenState();
}

class _ProductionCostScreenState extends State<ProductionCostScreen> {
  late final ProductionCostProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = ProductionCostProvider()..loadForSeason(widget.season.id);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final record = await showDialog<ProductionCostModel>(
      context: context,
      builder: (_) => _CostForm(season: widget.season),
    );
    if (record != null) await _provider.save(record);
  }

  Future<void> _delete(ProductionCostModel record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa khoản chi?'),
        content: Text('${record.itemName}: ${_money(record.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirmed == true) await _provider.delete(record);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chi phí • ${widget.season.name}'),
        actions: [
          IconButton(
            tooltip: 'Dashboard giá thành',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductionCostDashboardScreen(season: widget.season),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          if (_provider.isLoading) return const Center(child: CircularProgressIndicator());
          final records = _provider.recordsForSeason(widget.season.id);
          final total = _provider.totalCost(widget.season.id);
          final byCategory = _provider.byCategory(widget.season.id);
          final ha = widget.season.plannedArea / 10000;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Tổng chi phí sản xuất', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(_money(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('Chi phí/ha: ${_money(ha > 0 ? total / ha : 0)}'),
                    const SizedBox(height: 14),
                    ...ProductionCostCategory.values.map((category) {
                      final amount = byCategory[category] ?? 0;
                      final ratio = total > 0 ? amount / total : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Expanded(child: Text(category.label)), Text(_money(amount))]),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble()),
                        ]),
                      );
                    }),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Chưa có khoản chi trực tiếp cho vụ này.'))),
              ...records.map((record) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_icon(record.category))),
                      title: Text(record.itemName),
                      subtitle: Text(
                        '${record.category.label} • ${_date(record.date)}\n'
                        '${record.quantity.toStringAsFixed(2)} ${record.unit} × ${_money(record.unitPrice)} = ${_money(record.amount)}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(record)),
                    ),
                  )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Ghi chi phí'),
      ),
    );
  }

  IconData _icon(ProductionCostCategory category) {
    switch (category) {
      case ProductionCostCategory.material:
        return Icons.inventory_2;
      case ProductionCostCategory.labor:
        return Icons.groups;
      case ProductionCostCategory.machine:
        return Icons.precision_manufacturing;
      case ProductionCostCategory.fuel:
        return Icons.local_gas_station;
    }
  }

  String _money(double value) => '${value.toStringAsFixed(0)} đ';
  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _CostForm extends StatefulWidget {
  final ProductionSeasonModel season;
  const _CostForm({required this.season});

  @override
  State<_CostForm> createState() => _CostFormState();
}

class _CostFormState extends State<_CostForm> {
  final _item = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: 'lần');
  final _unitPrice = TextEditingController();
  final _notes = TextEditingController();
  ProductionCostCategory _category = ProductionCostCategory.material;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    for (final c in [_item, _quantity, _unit, _unitPrice, _notes]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ghi khoản chi sản xuất'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<ProductionCostCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Nhóm chi phí'),
            items: ProductionCostCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          TextField(controller: _item, decoration: const InputDecoration(labelText: 'Nội dung *')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ngày'),
            subtitle: Text(_format(_date)),
            onTap: () async {
              final value = await showDatePicker(context: context, firstDate: widget.season.startDate, lastDate: DateTime(2100), initialDate: _date);
              if (value != null) setState(() => _date = value);
            },
          ),
          TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Số lượng / giờ công')),
          TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Đơn vị (kg, ngày, giờ, lít...)')),
          TextField(controller: _unitPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Đơn giá (VNĐ)')),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Ghi chú')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: () {
            final item = _item.text.trim();
            final quantity = double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0;
            final price = double.tryParse(_unitPrice.text.replaceAll(',', '.')) ?? 0;
            if (item.isEmpty || quantity <= 0 || price < 0) return;
            Navigator.pop(
              context,
              ProductionCostModel(
                id: 'CP-${DateTime.now().microsecondsSinceEpoch}',
                fieldId: widget.season.fieldId,
                seasonId: widget.season.id,
                category: _category,
                date: _date,
                itemName: item,
                quantity: quantity,
                unit: _unit.text.trim().isEmpty ? 'lần' : _unit.text.trim(),
                unitPrice: price,
                amount: quantity * price,
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }

  String _format(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
