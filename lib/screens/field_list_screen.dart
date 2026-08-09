import 'package:flutter/material.dart';

import '../providers/field_provider.dart';
import 'field_detail_screen.dart';
import 'field_gps_measure_screen.dart';

class FieldListScreen extends StatelessWidget {
  const FieldListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = FieldProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách Lô đất'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Đo thửa bằng GPS',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen()),
            ),
            icon: const Icon(Icons.gps_fixed),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: provider,
        builder: (context, _) {
          final fields = provider.fields;
          return ListView.builder(
            itemCount: fields.length,
            itemBuilder: (ctx, index) {
              final field = fields[index];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.map, color: Colors.green),
                  title: Text(field.name),
                  subtitle: Text('${field.area.toStringAsFixed(1)} m² - ${field.crop} - ${field.status}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FieldDetailScreen(field: field)),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen()),
        ),
        icon: const Icon(Icons.gps_fixed),
        label: const Text('Đo GPS'),
      ),
    );
  }
}
