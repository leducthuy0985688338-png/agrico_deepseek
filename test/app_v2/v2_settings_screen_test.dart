import 'package:agrico_deepseek/app_v2/v2_settings_screen.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'catalog sync tile is available only with an authorized callback',
    (tester) async {
      var opens = 0;
      Widget app(VoidCallback? callback) => MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: V2SettingsScreen(onOpenCatalogSync: callback),
      );
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('company-catalog-sync-open')), findsNothing);
      await tester.pumpWidget(app(() => opens++));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('company-catalog-sync-open')));
      expect(opens, 1);
    },
  );

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
