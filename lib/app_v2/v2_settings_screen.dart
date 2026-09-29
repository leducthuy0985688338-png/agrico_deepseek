import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';

class V2SettingsScreen extends StatelessWidget {
  const V2SettingsScreen({super.key, this.onOpenBackup});

  final VoidCallback? onOpenBackup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('profile.settings'))),
      body: ListView(
        children: [
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
