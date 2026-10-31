import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';

class V2SettingsScreen extends StatelessWidget {
  const V2SettingsScreen({
    super.key,
    this.onOpenBackup,
    this.onSignOut,
    this.onOpenAccounts,
    this.onOpenApprovalPolicies,
    this.onOpenCatalog,
    this.onOpenCatalogSync,
    this.sessionOffline = false,
    this.offlineUntil,
  });

  final VoidCallback? onOpenBackup;
  final VoidCallback? onSignOut;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenApprovalPolicies;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onOpenCatalogSync;
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
          if (onOpenCatalog != null)
            ListTile(
              key: const Key('company-catalog-open'),
              leading: const Icon(Icons.category_outlined),
              title: Text(l10n.text('catalog.title')),
              onTap: onOpenCatalog,
            ),
          if (onOpenCatalogSync != null)
            ListTile(
              key: const Key('company-catalog-sync-open'),
              leading: const Icon(Icons.sync),
              title: Text(l10n.text('catalogSync.title')),
              onTap: onOpenCatalogSync,
            ),
          if (onOpenApprovalPolicies != null)
            ListTile(
              key: const Key('company-approval-policy-open'),
              leading: const Icon(Icons.policy_outlined),
              title: Text(switch (l10n.locale.languageCode) {
                'vi' => 'Chính sách phê duyệt',
                'lo' => 'ນະໂຍບາຍອະນຸມັດ',
                _ => 'Approval policy',
              }),
              onTap: onOpenApprovalPolicies,
            ),
          if (onOpenAccounts != null)
            ListTile(
              key: const Key('company-account-admin'),
              leading: const Icon(Icons.manage_accounts),
              title: Text(l10n.text('accounts.title')),
              onTap: onOpenAccounts,
            ),
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
