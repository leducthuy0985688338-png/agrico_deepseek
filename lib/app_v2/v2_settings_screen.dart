import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';

class V2SettingsScreen extends StatelessWidget {
  const V2SettingsScreen({
    super.key,
    this.onOpenBackup,
    this.onSignOut,
    this.sessionOffline = false,
    this.offlineUntil,
  });

  final VoidCallback? onOpenBackup;
  final VoidCallback? onSignOut;
  final bool sessionOffline;
  final DateTime? offlineUntil;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('profile.settings'))),
      body: ListView(
        children: [
          if (onSignOut != null) ...[
            ListTile(
              title: Text(
                l10n.text(
                  sessionOffline ? 'auth.offlineMode' : 'auth.onlineMode',
                ),
              ),
              subtitle: offlineUntil == null
                  ? null
                  : Text(offlineUntil!.toLocal().toString()),
            ),
            ListTile(
              key: const Key('company-sign-out'),
              leading: const Icon(Icons.logout),
              title: Text(l10n.text('auth.signOut')),
              onTap: onSignOut,
            ),
          ],
          ListTile(
            key: const Key('v2-settings-backup'),
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.text('module.backup')),
            subtitle: onOpenBackup == null
                ? Text(l10n.text('common.unavailable'))
                : null,
            onTap: onOpenBackup,
          ),
        ],
      ),
    );
  }
}
