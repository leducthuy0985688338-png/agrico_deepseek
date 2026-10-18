import 'package:agrico_deepseek/screens/warehouse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legacy warehouse route has no independent write actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WarehouseScreen()));
    expect(find.textContaining('Kho cũ đã ngừng hoạt động'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.add_box), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
  });
}
