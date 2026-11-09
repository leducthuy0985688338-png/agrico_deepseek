import 'package:agrico_deepseek/providers/machine_provider.dart';
import 'package:agrico_deepseek/providers/employee_provider.dart';
import 'package:agrico_deepseek/providers/finance_provider.dart';
import 'package:agrico_deepseek/providers/fuel_provider.dart';
import 'package:agrico_deepseek/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy AI never reports its empty warehouse as authoritative V2 stock', () {
    final machine = MachineProvider();
    final employee = EmployeeProvider();
    final finance = FinanceProvider();
    final fuel = FuelProvider();

    String ask(String question) => AIService.processQuestion(
      question, machine, employee, finance, fuel,
    );

    expect(ask('tồn kho'), contains('Kho AGRICO V2'));
    expect(ask('tồn kho'), isNot(contains('Số loại hàng: 0')));
    expect(ask('tổng quan'), contains('Kho AGRICO V2'));

    machine.dispose();
    employee.dispose();
    finance.dispose();
    fuel.dispose();
  });
}
