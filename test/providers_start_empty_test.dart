import 'package:agrico_deepseek/providers/employee_provider.dart';
import 'package:agrico_deepseek/providers/finance_provider.dart';
import 'package:agrico_deepseek/providers/fuel_provider.dart';
import 'package:agrico_deepseek/providers/machine_provider.dart';
import 'package:agrico_deepseek/providers/task_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy providers do not create sample business records', () {
    final machines = MachineProvider();
    final employees = EmployeeProvider();
    final tasks = TaskProvider();
    final finance = FinanceProvider();
    final fuel = FuelProvider();

    expect(machines.machines, isEmpty);
    expect(employees.employees, isEmpty);
    expect(employees.attendanceLogs, isEmpty);
    expect(tasks.tasks, isEmpty);
    expect(finance.records, isEmpty);
    expect(finance.budgets, isEmpty);
    expect(fuel.fuels, isEmpty);
    expect(fuel.allTransactions, isEmpty);

    machines.dispose();
    employees.dispose();
    tasks.dispose();
    finance.dispose();
    fuel.dispose();
  });
}
