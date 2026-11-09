import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/household_directory_query.dart';
import '../../domain/entities/land_survey.dart';

class HouseholdDirectoryScreen extends StatefulWidget {
  const HouseholdDirectoryScreen({
    super.key,
    required this.query,
    required this.subject,
    this.onOpenHousehold,
    this.onCreate,
  });

  final HouseholdDirectoryQuery query;
  final AuthorizationSubject subject;
  final Future<void> Function(String)? onOpenHousehold;
  final Future<void> Function()? onCreate;

  @override
  State<HouseholdDirectoryScreen> createState() =>
      _HouseholdDirectoryScreenState();
}

class _HouseholdDirectoryScreenState extends State<HouseholdDirectoryScreen> {
  late Future<List<Household>> households;
  String search = '';

  @override
  void initState() {
    super.initState();
    households = widget.query.list(widget.subject);
  }

  void reload() => setState(() {
    households = widget.query.list(widget.subject);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('household.directory')),
        actions: [IconButton(
          tooltip: l10n.text('common.retry'),
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        )],
      ),
      floatingActionButton: widget.onCreate == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('household-add'),
              onPressed: () async {
                await widget.onCreate!();
                if (mounted) reload();
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.text('household.add')),
            ),
      body: FutureBuilder<List<Household>>(
        future: households,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.text('household.loadFailed')),
                TextButton(onPressed: reload,
                    child: Text(l10n.text('common.retry'))),
              ],
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final term = search.trim().toLowerCase();
          final visible = all.where((household) =>
              household.householdCode.toLowerCase().contains(term) ||
              household.headOfHouseholdName.toLowerCase().contains(term) ||
              household.administrativeLocation.villageName
                  .toLowerCase().contains(term)).toList()
            ..sort((a, b) => a.householdCode.compareTo(b.householdCode));
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('household-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: l10n.text('household.search'),
                ),
                onChanged: (value) => setState(() => search = value),
              ),
            ),
            Expanded(child: visible.isEmpty
                ? Center(child: Text(l10n.text(all.isEmpty
                    ? 'household.empty' : 'household.noMatches')))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final household = visible[index];
                      return ListTile(
                        key: Key('household-${household.id}'),
                        title: Text('${household.householdCode} · '
                            '${household.headOfHouseholdName}'),
                        subtitle: Text([
                          household.administrativeLocation.villageName,
                          household.administrativeLocation.districtName,
                        ].where((value) => value.isNotEmpty).join(' · ')),
                        trailing: household.active
                            ? null
                            : Text(l10n.text('common.inactive')),
                        onTap: widget.onOpenHousehold == null
                            ? null
                            : () async {
                                await widget.onOpenHousehold!(household.id);
                                if (mounted) reload();
                              },
                      );
                    },
                  )),
          ]);
        },
      ),
    );
  }
}
