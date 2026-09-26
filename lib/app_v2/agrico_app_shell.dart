import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_locale_controller.dart';
import '../core/localization/app_localizations.dart';
import '../core/permissions/authorization.dart';
import '../features/farm/presentation/controllers/land_parcel_controller.dart';

enum AppDestination { home, modules, create, reports, profile }

class AgricoAppShell extends StatefulWidget {
  const AgricoAppShell({
    super.key,
    required this.subject,
    required this.landParcelController,
    required this.openLandParcels,
    required this.openCreateParcel,
    required this.legacyRoutes,
    this.parcelCount,
    this.seasonCount,
    this.taskCount,
    this.alertCount,
    this.farmName,
  });
  final AuthorizationSubject subject;
  final LandParcelController landParcelController;
  final VoidCallback openLandParcels;
  final VoidCallback openCreateParcel;
  final Map<String, VoidCallback> legacyRoutes;
  final int? parcelCount;
  final int? seasonCount;
  final int? taskCount;
  final int? alertCount;
  final String? farmName;

  @override
  State<AgricoAppShell> createState() => _AgricoAppShellState();
}

class _AgricoAppShellState extends State<AgricoAppShell> {
  AppDestination selected = AppDestination.home;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = <AppDestination, Widget>{
      AppDestination.home: HomeV2(
        parcelCount: widget.parcelCount,
        seasonCount: widget.seasonCount,
        taskCount: widget.taskCount,
        alertCount: widget.alertCount,
        farmName: widget.farmName,
        openLandParcels: widget.openLandParcels,
        legacyRoutes: widget.legacyRoutes,
        canViewParcels: widget.landParcelController.can(
          PermissionCodes.fieldView,
        ),
      ),
      AppDestination.modules: ModulesV2(
        subject: widget.subject,
        openLandParcels: widget.openLandParcels,
        legacyRoutes: widget.legacyRoutes,
      ),
      AppDestination.reports: _EntryPage(
        icon: Icons.assessment_outlined,
        title: l10n.text('nav.reports'),
        action: widget.legacyRoutes['reports'],
      ),
      AppDestination.profile: ProfileV2(
        subject: widget.subject,
        settings: widget.legacyRoutes['settings'],
      ),
    };
    return PopScope(
      canPop: selected == AppDestination.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selected != AppDestination.home) {
          setState(() => selected = AppDestination.home);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: [
              AppDestination.home,
              AppDestination.modules,
              AppDestination.reports,
              AppDestination.profile,
            ].indexOf(selected),
            children: [
              pages[AppDestination.home]!,
              pages[AppDestination.modules]!,
              pages[AppDestination.reports]!,
              pages[AppDestination.profile]!,
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected == AppDestination.create
              ? 0
              : AppDestination.values.indexOf(selected),
          onDestinationSelected: _select,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.text('nav.home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view),
              label: l10n.text('nav.modules'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.add_circle, size: 36),
              label: l10n.text('nav.create'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.assessment_outlined),
              selectedIcon: const Icon(Icons.assessment),
              label: l10n.text('nav.reports'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.text('nav.profile'),
            ),
          ],
        ),
      ),
    );
  }

  void _select(int index) {
    final destination = AppDestination.values[index];
    if (destination == AppDestination.create) {
      _quickCreate();
      return;
    }
    setState(() => selected = destination);
  }

  void _quickCreate() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(l10n.text('module.parcels')),
              enabled: widget.landParcelController.can(
                PermissionCodes.fieldCreate,
              ),
              onTap: () {
                Navigator.pop(context);
                widget.openCreateParcel();
              },
            ),
            for (final item in const [
              'logs',
              'harvest',
              'costs',
              'employees',
              'machines',
              'tasks',
              'other',
            ])
              ListTile(
                title: Text(l10n.text('quickCreate.$item')),
                subtitle: Text(l10n.text('common.unavailable')),
                enabled: false,
              ),
          ],
        ),
      ),
    );
  }
}

class HomeV2 extends StatelessWidget {
  const HomeV2({
    super.key,
    required this.openLandParcels,
    required this.legacyRoutes,
    this.parcelCount,
    this.seasonCount,
    this.taskCount,
    this.alertCount,
    this.farmName,
    this.canViewParcels = false,
  });
  final VoidCallback openLandParcels;
  final Map<String, VoidCallback> legacyRoutes;
  final int? parcelCount, seasonCount, taskCount, alertCount;
  final String? farmName;
  final bool canViewParcels;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const Key('home-v2'),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.agriculture)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('home.greeting'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(farmName ?? l10n.text('home.farmUnavailable')),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none),
                ),
                IconButton(
                  onPressed: null,
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
              ],
            ),
          ),
        ),
        _SectionTitle(l10n.text('home.kpi')),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.8,
          children: [
            _Kpi(l10n.text('kpi.parcels'), parcelCount),
            _Kpi(l10n.text('kpi.seasons'), seasonCount),
            _Kpi(l10n.text('kpi.tasks'), taskCount),
            _Kpi(l10n.text('kpi.alerts'), alertCount),
          ],
        ),
        _SectionTitle(l10n.text('home.quickActions')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.map_outlined),
              label: Text(l10n.text('module.parcels')),
              onPressed: canViewParcels ? openLandParcels : null,
            ),
            ActionChip(
              label: Text(l10n.text('module.productionLogs')),
              onPressed: legacyRoutes['productionLogs'],
            ),
            ActionChip(
              label: Text(l10n.text('module.resources')),
              onPressed: legacyRoutes['machines'],
            ),
            ActionChip(
              label: Text(l10n.text('module.finance')),
              onPressed: legacyRoutes['finance'],
            ),
          ],
        ),
        _SectionTitle(l10n.text('home.farmOverview')),
        Text(l10n.text('common.unavailable')),
        _SectionTitle(l10n.text('home.recentActivity')),
        Text(l10n.text('common.empty')),
      ],
    );
  }
}

class ModulesV2 extends StatelessWidget {
  const ModulesV2({
    super.key,
    required this.subject,
    required this.openLandParcels,
    required this.legacyRoutes,
  });
  final AuthorizationSubject subject;
  final VoidCallback openLandParcels;
  final Map<String, VoidCallback> legacyRoutes;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const Key('modules-v2'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.text('modules.title'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        _group(context, 'modules.production', {
          'parcels': subject.permissionCodes.contains(PermissionCodes.fieldView)
              ? openLandParcels
              : null,
          'seasons': legacyRoutes['seasons'],
          'productionLogs': legacyRoutes['productionLogs'],
          'harvest': legacyRoutes['harvest'],
        }),
        _group(context, 'modules.resources', {
          'employees': legacyRoutes['employees'],
          'machines': legacyRoutes['machines'],
          'warehouse': legacyRoutes['warehouse'],
          'fuel': legacyRoutes['fuel'],
        }),
        _group(context, 'modules.finance', {
          'costs': legacyRoutes['costs'],
          'finance': legacyRoutes['finance'],
        }),
        _group(context, 'modules.support', {
          'backup': legacyRoutes['backup'],
          'administrativeCatalog': legacyRoutes['administrativeCatalog'],
          'tasks': legacyRoutes['tasks'],
          'ai': legacyRoutes['ai'],
          'cloud': legacyRoutes['settings'],
        }),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    Map<String, VoidCallback?> items,
  ) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            AppLocalizations.of(context).text(title),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...items.entries.map(
          (item) => ListTile(
            title: Text(
              AppLocalizations.of(context).text('module.${item.key}'),
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: item.value != null,
            onTap: item.value,
          ),
        ),
      ],
    ),
  );
}

class ProfileV2 extends StatelessWidget {
  const ProfileV2({super.key, required this.subject, this.settings});
  final AuthorizationSubject subject;
  final VoidCallback? settings;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const Key('profile-v2'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.text('profile.title'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(subject.userId),
          subtitle: Text(subject.membershipId),
        ),
        Text(l10n.text('profile.language')),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'vi', label: Text('Tiếng Việt')),
            ButtonSegment(value: 'lo', label: Text('ລາວ')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {context.watch<AppLocaleController>().locale.languageCode},
          onSelectionChanged: (value) => context
              .read<AppLocaleController>()
              .setLocale(Locale(value.single)),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: Text(l10n.text('profile.settings')),
          onTap: settings,
        ),
      ],
    );
  }
}

class _EntryPage extends StatelessWidget {
  const _EntryPage({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        FilledButton(
          onPressed: action,
          child: Text(AppLocalizations.of(context).text('common.open')),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);
  final String label;
  final int? value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value?.toString() ?? '—',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(label, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}
