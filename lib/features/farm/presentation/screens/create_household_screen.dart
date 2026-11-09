import 'package:flutter/material.dart';

import '../../../../core/geography/domain/entities/administrative_unit.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/create_household.dart';
import '../../domain/entities/land_survey.dart';

class CreateHouseholdScreen extends StatefulWidget {
  const CreateHouseholdScreen({
    super.key,
    required this.create,
    required this.subject,
    required this.loadUnits,
  });

  final CreateHousehold create;
  final AuthorizationSubject subject;
  final Future<List<AdministrativeUnit>> Function() loadUnits;

  @override
  State<CreateHouseholdScreen> createState() => _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends State<CreateHouseholdScreen> {
  late final Future<List<AdministrativeUnit>> units;
  String? villageId;
  String name = '';
  String phone = '';
  String contact = '';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    units = widget.loadUnits();
  }

  Future<void> save(String selected) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final Household created = await widget.create.execute(
        subject: widget.subject, villageId: selected, headName: name,
        phone: phone, alternativeContact: contact,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).text('household.saveFailed')),
      ));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('household.add'))),
      body: FutureBuilder<List<AdministrativeUnit>>(
        future: units,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('admin.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final byId = {for (final unit in snapshot.data!) unit.id: unit};
          final paths = <(AdministrativeUnit, String)>[];
          for (final village in snapshot.data!) {
            if (!village.active || village.level != AdministrativeLevel.village ||
                village.code == null) continue;
            final district = byId[village.parentId];
            final province = byId[district?.parentId];
            final country = byId[province?.parentId];
            if (district == null || province == null || country == null ||
                !district.active || !province.active || !country.active ||
                district.level != AdministrativeLevel.district ||
                province.level != AdministrativeLevel.province ||
                country.level != AdministrativeLevel.country) continue;
            paths.add((village,
              '${country.name} · ${province.name} · ${district.name} · ${village.name}'));
          }
          if (paths.isEmpty) {
            return Center(child: Text(l10n.text('household.noVillages')));
          }
          final selected = paths.any((path) => path.$1.id == villageId)
              ? villageId : paths.first.$1.id;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(l10n.text('household.codeAutomatic')),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('household-village'),
              isExpanded: true,
              initialValue: selected,
              decoration: InputDecoration(labelText: l10n.text('admin.village')),
              items: [for (final path in paths)
                DropdownMenuItem(value: path.$1.id,
                  child: Text(path.$2, overflow: TextOverflow.ellipsis))],
              onChanged: saving ? null : (value) =>
                  setState(() => villageId = value),
            ),
            TextField(
              key: const Key('household-head'),
              decoration: InputDecoration(labelText: l10n.text('household.head')),
              onChanged: (value) => setState(() => name = value),
            ),
            TextField(
              key: const Key('household-phone'),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: l10n.text('household.phone')),
              onChanged: (value) => phone = value,
            ),
            TextField(
              key: const Key('household-contact'),
              decoration: InputDecoration(
                  labelText: l10n.text('household.alternativeContact')),
              onChanged: (value) => contact = value,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('household-save'),
              onPressed: saving || name.trim().isEmpty
                  ? null : () => save(selected!),
              child: Text(l10n.text('common.save')),
            ),
            if (saving) const Center(child: CircularProgressIndicator()),
          ]);
        },
      ),
    );
  }
}
