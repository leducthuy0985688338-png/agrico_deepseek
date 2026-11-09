import 'package:agrico_deepseek/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final groups = <String, List<String>>{
    'catalog': ['Danh mục', 'Đề xuất'],
    'personnel': ['Nhân sự', 'Chấm công', 'Mức lương', 'Bảng lương'],
    'machines': [
      'Máy móc',
      'Nhật ký ca máy',
      'Giá ca máy',
      'Nhiên liệu',
      'Bảo dưỡng',
    ],
    'trade': [
      'Thu hoạch',
      'Bán hàng',
      'Mua vật tư',
      'Khoản phải trả khác',
      'Lô thành phẩm',
      'Công nợ',
      'Thu/chi',
    ],
    'English': ['Employees', 'Attendance', 'Rates', 'Payroll'],
    'Lao': ['ບຸກຄະລາກອນ', 'ລົງເວລາ', 'ອັດຕາຄ່າແຮງ'],
  };

  test(
    'both tab states have readable contrast on the actual AppBar background',
    () {
      final theme = AppTheme.lightTheme;
      final background = theme.appBarTheme.backgroundColor!.computeLuminance();
      for (final color in [
        theme.tabBarTheme.labelColor!,
        theme.tabBarTheme.unselectedLabelColor!,
      ]) {
        final foreground = color.computeLuminance();
        final lighter = foreground > background ? foreground : background;
        final darker = foreground > background ? background : foreground;
        expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
      }
    },
  );

  for (final group in groups.entries) {
    testWidgets(
      '${group.key} selected names remain visible after every tab change',
      (tester) async {
        final names = group.value;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: DefaultTabController(
              length: names.length,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('AGRICO'),
                  bottom: TabBar(
                    isScrollable: true,
                    tabs: [for (final name in names) Tab(text: name)],
                  ),
                ),
                body: TabBarView(
                  children: [
                    for (final name in names)
                      Center(child: Text('Body: $name')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Color? labelColor(String name) {
          final text = tester.widget<RichText>(
            find.descendant(
              of: find.text(name),
              matching: find.byType(RichText),
            ),
          );
          return text.text.style?.color;
        }

        for (final selected in names) {
          await tester.ensureVisible(find.text(selected));
          await tester.tap(find.text(selected));
          await tester.pumpAndSettle();
          expect(labelColor(selected), Colors.white);
          expect(find.text('Body: $selected'), findsOneWidget);
          for (final other in names.where((name) => name != selected)) {
            expect(labelColor(other), const Color(0xFFE8F5E9));
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
