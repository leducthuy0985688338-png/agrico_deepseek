import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/harvest_record_model.dart';
import '../models/production_season_model.dart';
import '../providers/harvest_provider.dart';

class HarvestScreen extends StatefulWidget {
  final ProductionSeasonModel season;
  const HarvestScreen({super.key, required this.season});

  @override
  State<HarvestScreen> createState() => _HarvestScreenState();
}

class _HarvestScreenState extends State<HarvestScreen> {
  late final HarvestProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<HarvestProvider>()
      ..loadForSeason(widget.season.id);
  }

  Future<void> _add() async {
    final record = await showDialog<HarvestRecordModel>(
      context: context,
      builder: (_) => _HarvestForm(season: widget.season),
    );
    if (record != null) await _provider.save(record);
  }

  Future<void> _delete(HarvestRecordModel record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bản ghi?'),
        content: Text('Xóa ${record.quantity} ${record.unit} ngày ${_date(record.date)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) await _provider.delete(record);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Thu hoạch • ${widget.season.name}')),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          if (_provider.isLoading) return const Center(child: CircularProgressIndicator());
          final records = _provider.recordsForSeason(widget.season.id);
          final total = _provider.totalQuantity(widget.season.id);
          final revenue = _provider.totalRevenue(widget.season.id);
          final hectares = widget.season.plannedArea / 10000;
          final yieldPerHa = hectares > 0 ? total / hectares : 0;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 14,
                    children: [
                      _Metric('Sản lượng', '${total.toStringAsFixed(1)} kg'),
                      _Metric('Năng suất/ha', '${yieldPerHa.toStringAsFixed(1)} kg/ha'),
                      _Metric('Doanh thu', '${revenue.toStringAsFixed(0)} đ'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Chưa có dữ liệu thu hoạch.'))),
              ...records.map((record) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.agriculture)),
                      title: Text('${record.quantity.toStringAsFixed(1)} ${record.unit}'),
                      subtitle: Text('${_date(record.date)} • ${record.sellingPrice.toStringAsFixed(0)} đ/${record.unit}\nĐộ ẩm: ${record.moisturePercent.toStringAsFixed(1)}% • Doanh thu: ${record.revenue > 0 ? record.revenue.toStringAsFixed(0) : (record.quantity * record.sellingPrice).toStringAsFixed(0)} đ'),
                      isThreeLine: true,
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(record)),
                    ),
                  )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Ghi thu hoạch')),
    );
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]);
}

class _HarvestForm extends StatefulWidget {
  final ProductionSeasonModel season;
  const _HarvestForm({required this.season});
  @override
  State<_HarvestForm> createState() => _HarvestFormState();
}

class _HarvestFormState extends State<_HarvestForm> {
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _moisture = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _unit = 'kg';

  @override
  void dispose() { for (final c in [_quantity, _price, _moisture, _notes]) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ghi nhận thu hoạch'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Ngày thu hoạch'), subtitle: Text(_fmt(_date)), onTap: () async { final d = await showDatePicker(context: context, firstDate: widget.season.startDate, lastDate: DateTime(2100), initialDate: _date); if (d != null) setState(() => _date = d); }),
          TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Sản lượng *')),
          DropdownButtonFormField<String>(initialValue: _unit, decoration: const InputDecoration(labelText: 'Đơn vị'), items: const ['kg', 'tấn', 'bao'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (v) => setState(() => _unit = v ?? _unit)),
          TextField(controller: _price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Giá bán / $_unit (VNĐ)')),
          TextField(controller: _moisture, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Độ ẩm (%)')),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Ghi chú')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')), FilledButton(onPressed: () { final quantity = double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0; if (quantity <= 0) return; final price = double.tryParse(_price.text.replaceAll(',', '.')) ?? 0; Navigator.pop(context, HarvestRecordModel(id: 'TH-${DateTime.now().microsecondsSinceEpoch}', seasonId: widget.season.id, fieldId: widget.season.fieldId, date: _date, quantity: quantity, unit: _unit, moisturePercent: double.tryParse(_moisture.text.replaceAll(',', '.')) ?? 0, sellingPrice: price, revenue: quantity * price, notes: _notes.text.trim())); }, child: const Text('Lưu'))],
      );

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
