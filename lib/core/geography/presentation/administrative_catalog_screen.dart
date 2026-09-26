import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../permissions/authorization.dart';
import '../application/manage_administrative_catalog.dart';
import '../domain/entities/administrative_unit.dart';

class AdministrativeCatalogScreen extends StatefulWidget {
  const AdministrativeCatalogScreen({
    super.key,
    required this.catalog,
    required this.subject,
  });

  final ManageAdministrativeCatalog catalog;
  final AuthorizationSubject subject;

  @override
  State<AdministrativeCatalogScreen> createState() =>
      _AdministrativeCatalogScreenState();
}

class _AdministrativeCatalogScreenState extends State<AdministrativeCatalogScreen> {
  late Future<List<AdministrativeUnit>> units = widget.catalog.all();

  Future<void> _add(List<AdministrativeUnit> current) async {
    final name = TextEditingController();
    final code = TextEditingController();
    final alternate = TextEditingController();
    var level = AdministrativeLevel.province;
    String? parentId;
    String? error;
    var saving = false;
    final l10n = AppLocalizations.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) {
          final parentLevel = switch (level) {
            AdministrativeLevel.province => AdministrativeLevel.country,
            AdministrativeLevel.district => AdministrativeLevel.province,
            _ => AdministrativeLevel.district,
          };
          final parents = current.where((unit) =>
              unit.active && unit.level == parentLevel).toList();
          final selected = parents.any((unit) => unit.id == parentId)
              ? parentId : (parents.isEmpty ? null : parents.first.id);
          return AlertDialog(
            title: Text(l10n.text('admin.add')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<AdministrativeLevel>(
                  key: const Key('admin-level'),
                  initialValue: level,
                  decoration: InputDecoration(labelText: l10n.text('admin.level')),
                  items: [
                    for (final value in const [
                      AdministrativeLevel.province,
                      AdministrativeLevel.district,
                      AdministrativeLevel.village,
                    ])
                      DropdownMenuItem(value: value,
                          child: Text(l10n.text('admin.${value.name}'))),
                  ],
                  onChanged: saving ? null : (value) => update(() {
                    level = value!;
                    parentId = null;
                    error = null;
                  }),
                ),
                DropdownButtonFormField<String>(
                  key: Key('admin-parent-${level.name}'),
                  initialValue: selected,
                  decoration: InputDecoration(labelText: l10n.text('admin.parent')),
                  items: [for (final unit in parents)
                    DropdownMenuItem(value: unit.id,
                        child: Text('${unit.name} (${unit.code})'))],
                  onChanged: saving ? null : (value) => update(() => parentId = value),
                ),
                TextField(key: const Key('admin-name'), controller: name,
                    decoration: InputDecoration(labelText: l10n.text('admin.name'))),
                TextField(key: const Key('admin-code'), controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: l10n.text('admin.code'))),
                TextField(key: const Key('admin-alternate'), controller: alternate,
                    decoration: InputDecoration(labelText: l10n.text('admin.alternate'))),
                if (error != null) Text(error!,
                    key: const Key('admin-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: Text(l10n.text('common.cancel'))),
              FilledButton(
                key: const Key('admin-save'),
                onPressed: saving ? null : () async {
                  if (selected == null) {
                    update(() => error = l10n.text('admin.parentRequired'));
                    return;
                  }
                  update(() { saving = true; error = null; });
                  try {
                    await widget.catalog.add(
                      subject: widget.subject, level: level, parentId: selected,
                      name: name.text, code: code.text,
                      alternateName: alternate.text,
                    );
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (mounted) setState(() => units = widget.catalog.all());
                  } catch (_) {
                    if (dialogContext.mounted) {
                      update(() {
                        saving = false;
                        error = l10n.text('admin.saveFailed');
                      });
                    }
                  }
                },
                child: Text(l10n.text('common.save')),
              ),
            ],
          );
        },
      ),
    );
    // The dialog has been removed before its controllers are released.
    name.dispose();
    code.dispose();
    alternate.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('admin.title'))),
      body: FutureBuilder<List<AdministrativeUnit>>(
        future: units,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(l10n.text('admin.loadFailed')));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final all = snapshot.data!;
          final names = {for (final unit in all) unit.id: unit.name};
          return ListView(
            key: const Key('admin-list'),
            children: [
              Padding(padding: const EdgeInsets.all(16),
                  child: Text(l10n.text('admin.internalCodes'))),
              for (final unit in all)
                ListTile(
                  key: Key('admin-unit-${unit.id}'),
                  title: Text('${unit.name} · ${unit.code}'),
                  subtitle: Text('${l10n.text('admin.${unit.level.name}')} · '
                      '${names[unit.parentId] ?? l10n.text('admin.root')}'),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin-add'),
        onPressed: () async {
          final current = await units;
          if (mounted) await _add(current);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.text('admin.add')),
      ),
    );
  }
}
