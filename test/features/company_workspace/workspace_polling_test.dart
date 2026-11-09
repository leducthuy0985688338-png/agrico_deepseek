import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/features/company_workspace/presentation/workspace_polling.dart';

class Probe extends StatefulWidget {
  const Probe({super.key, required this.refresh});
  final Future<void> Function() refresh;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe>
    with WidgetsBindingObserver, WorkspacePolling<Probe> {
  @override
  Future<void> refreshWorkspace() => widget.refresh();
  @override
  bool get workspaceChanged => false;
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('probe'));
}

void main() {
  testWidgets('idle polling backs off to 60s and stops in background', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Probe(
          refresh: () async {
            calls++;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 19));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 40));
    expect(calls, 3);
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 4);
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 5);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 5);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 6);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 6);
  });
  testWidgets('covered route cancels polling and uncovered route refreshes', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Probe(
          refresh: () async {
            calls++;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ),
    );
    await tester.pumpAndSettle();
    final before = calls;
    await tester.pump(const Duration(minutes: 3));
    expect(calls, before);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, before + 1);
    await tester.pumpWidget(const SizedBox());
  });
}
