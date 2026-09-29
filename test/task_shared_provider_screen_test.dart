import 'package:agrico_deepseek/providers/task_provider.dart';
import 'package:agrico_deepseek/screens/task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('new task appears in list through the app task provider', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    final tasks = TaskProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<TaskProvider>.value(
        value: tasks,
        child: const MaterialApp(home: TaskScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Khai hoang lô A');
    final save = find.text('Tạo công việc');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(tasks.tasks, hasLength(1));
    expect(tasks.tasks.single.title, 'Khai hoang lô A');
    expect(find.text('Khai hoang lô A'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    tasks.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
