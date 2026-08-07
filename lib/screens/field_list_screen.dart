import 'package:flutter/material.dart';
import '../providers/field_provider.dart';
import 'field_detail_screen.dart';

class FieldListScreen extends StatelessWidget {
  const FieldListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider =
        FieldProvider(); // Dùng trực tiếp (sau này sẽ dùng Riverpod)

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách Lô đất'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              // Thêm lô mới (sẽ hướng dẫn sau)
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: provider.fields.length,
        itemBuilder: (ctx, index) {
          final field = provider.fields[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: const Icon(Icons.map, color: Colors.green),
              title: Text(field.name),
              subtitle: Text(
                '${field.area} m² - ${field.crop} - ${field.status}',
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FieldDetailScreen(field: field),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
