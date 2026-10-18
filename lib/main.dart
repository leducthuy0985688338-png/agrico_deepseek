import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/localization/app_locale_controller.dart';
import 'app/legacy_provider_scope.dart';
import 'core/localization/app_localizations.dart';
import 'core/backup/local_restore_activation.dart';
import 'theme/app_theme.dart';
import 'services/cloud_service.dart';
import 'core/auth/company_access_gate.dart';

// Preserve imports used by existing compatibility callers.
export 'app/legacy_dashboard.dart' show DashboardScreen, HomePage, FarmPage;

// ====== ĐIỂM KHỞI ĐẦU ======
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyPendingRestore();
  await CloudService.initialize();
  runApp(const MyApp());
}

// ====== APP CHÍNH ======
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.homeOverride});

  final Widget? homeOverride;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppLocaleController()),
        ...buildLegacyProviders(),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          onGenerateTitle: (context) => context.l10n.text('app.name'),
          // Preserve the legacy Vietnamese default. A persisted user preference
          // will replace this initial value when settings persistence is migrated.
          locale: context.watch<AppLocaleController>().locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.lightTheme,
          home: homeOverride ?? const CompanyAccessGate(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
