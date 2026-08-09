import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';

class FieldEditScreen extends StatefulWidget {
  final FieldModel field;
  const FieldEditScreen({super.key, required this.field});

  @override
  State<FieldEditScreen> createState() => _FieldEditScreenState();
}

class _FieldEditScreenState extends State<FieldEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _crop = TextEditingController();
  final _status = TextEditingController();
  final _provider = FieldProvider();

  @override
  void initState() {
    super.initState();
    _name.text = widget.field.name;
    _crop.text = widget.field.crop;
    _status.text = widget.field.status;
  }

  @override
  void dispose() {
    _name.dispose();
    _crop.dispose();
    _status.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _provider.updateField(
      widget.field.copyWith(
        name: _name.text.trim(),
        crop: _crop.text.trim(),
        status: _status.text.trim(),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin thửa đất')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Tên lô / thửa',
                prefixIcon: Icon(Icons.landscape),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập tên lô'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _crop,
              decoration: const InputDecoration(
                labelText: 'Cây trồng',
                prefixIcon: Icon(Icons.grass),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập cây trồng'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _status,
              decoration: const InputDecoration(
                labelText: 'Trạng thái',
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập trạng thái'
                  : null,
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.square_foot),
                title: Text('${widget.field.area.toStringAsFixed(1)} m²'),
                subtitle: Text(
                  '${(widget.field.area / 10000).toStringAsFixed(3)} ha • ${widget.field.polygon.length} điểm GPS',
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('LƯU THÔNG TIN'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
