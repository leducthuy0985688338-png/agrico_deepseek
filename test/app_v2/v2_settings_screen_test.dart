import 'package:agrico_deepseek/app_v2/v2_settings_screen.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('v2 settings opens local backup', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: V2SettingsScreen(onOpenBackup: () => opened = true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('v2-settings-backup')), findsOneWidget);
    await tester.tap(find.byKey(const Key('v2-settings-backup')));
    expect(opened, isTrue);
  });
}
