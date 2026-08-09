import 'package:flutter/material.dart';

import '../providers/field_provider.dart';
import 'distance_measure_screen.dart';
import 'field_detail_screen.dart';
import 'field_gps_measure_screen.dart';
import 'field_map_screen.dart';
import 'field_measurement_history_screen.dart';

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
            tooltip: 'Bản đồ tổng thể',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FieldMapScreen()),
            ),
            icon: const Icon(Icons.map),
          ),
          IconButton(
            tooltip: 'Đo khoảng cách',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DistanceMeasureScreen()),
            ),
            icon: const Icon(Icons.straighten),
          ),
          IconButton(
            tooltip: 'Lịch sử đo khoảng cách',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DistanceHistoryScreen()),
            ),
            icon: const Icon(Icons.route),
          ),
          IconButton(
            tooltip: 'Lịch sử đo đạc',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FieldMeasurementHistoryScreen()),
            ),
            icon: const Icon(Icons.history),
          ),
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
                  subtitle: Text(
                    '${field.area.toStringAsFixed(1)} m² - ${field.crop} - ${field.status}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'history') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FieldMeasurementHistoryScreen(field: field),
                          ),
                        );
                      } else if (value == 'detail') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FieldDetailScreen(field: field),
                          ),
                        );
                      } else if (value == 'map') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FieldMapScreen()),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'detail', child: Text('Chi tiết thửa')),
                      PopupMenuItem(value: 'history', child: Text('Lịch sử đo đạc')),
                      PopupMenuItem(value: 'map', child: Text('Mở bản đồ tổng thể')),
                    ],
                  ),
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
          MaterialPageRoute(builder: (_) => const FieldMapScreen()),
        ),
        icon: const Icon(Icons.map),
        label: const Text('Bản đồ tổng thể'),
      ),
    );
  }
}
