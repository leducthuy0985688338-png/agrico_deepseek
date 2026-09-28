import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/household_detail_query.dart';

class HouseholdDetailScreen extends StatefulWidget {
  const HouseholdDetailScreen({
    super.key,
    required this.query,
    required this.subject,
    required this.householdId,
    required this.onOpenParcel,
  });

  final HouseholdDetailQuery query;
  final AuthorizationSubject subject;
  final String householdId;
  final ValueChanged<String> onOpenParcel;

  @override
  State<HouseholdDetailScreen> createState() => _HouseholdDetailScreenState();
}

class _HouseholdDetailScreenState extends State<HouseholdDetailScreen> {
  late Future<HouseholdWithParcels?> detail;

  @override
  void initState() {
    super.initState();
    detail = widget.query.load(widget.subject, widget.householdId);
  }

  void reload() => setState(() {
    detail = widget.query.load(widget.subject, widget.householdId);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('household.detail')),
        actions: [IconButton(
          tooltip: l10n.text('common.retry'),
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        )]),
      body: FutureBuilder<HouseholdWithParcels?>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('household.loadFailed')));
          }
          if (!snapshot.hasData && snapshot.connectionState !=
              ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return Center(child: Text(l10n.text('household.notFound')));
          }
          final household = data.household;
          final location = household.administrativeLocation;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${household.householdCode} · '
                '${household.headOfHouseholdName}',
                style: Theme.of(context).textTheme.titleLarge),
            if (!household.active) Text(l10n.text('common.inactive')),
            const SizedBox(height: 12),
            Text([location.villageName, location.districtName,
              location.provinceName, location.countryName]
                .where((value) => value.isNotEmpty).join(' · ')),
            if (household.phone != null) ListTile(
              title: Text(l10n.text('household.phone')),
              subtitle: Text(household.phone!),
            ),
            if (household.alternativeContact != null) ListTile(
              title: Text(l10n.text('household.alternativeContact')),
              subtitle: Text(household.alternativeContact!),
            ),
            const SizedBox(height: 16),
            Text(l10n.text('household.parcels'),
                style: Theme.of(context).textTheme.titleMedium),
            if (data.parcels.isEmpty) Text(l10n.text('household.noParcels')),
            for (final parcel in data.parcels)
              ListTile(
                key: Key('household-parcel-${parcel.id}'),
                title: Text('${parcel.parcelCode} · ${parcel.name}'),
                subtitle: parcel.active ? null
                    : Text(l10n.text('common.inactive')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onOpenParcel(parcel.id),
              ),
          ]);
        },
      ),
    );
  }
}
