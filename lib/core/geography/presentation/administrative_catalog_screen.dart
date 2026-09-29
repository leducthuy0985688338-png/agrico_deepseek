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
  List<AdministrativeUnit>? units;
  Object? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.catalog.all();
      if (mounted) {
        setState(() { units = result; loadError = null; });
      }
    } catch (error) {
      if (mounted) {
        setState(() => loadError = error);
      }
    }
  }

  Future<void> _add(List<AdministrativeUnit> current) async {
    var name = '';
    var code = '';
    var alternate = '';
    var level = AdministrativeLevel.province;
    String? parentId;
    String? error;
    final l10n = AppLocalizations.of(context);

    final draft = await showDialog<_AdministrativeAreaDraft>(
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
                  onChanged: (value) => update(() {
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
                  onChanged: (value) => update(() => parentId = value),
                ),
                TextField(key: const Key('admin-name'),
                    onChanged: (value) => name = value,
                    decoration: InputDecoration(labelText: l10n.text('admin.name'))),
                TextField(key: const Key('admin-code'),
                    onChanged: (value) => code = value,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: l10n.text('admin.code'))),
                TextField(key: const Key('admin-alternate'),
                    onChanged: (value) => alternate = value,
                    decoration: InputDecoration(labelText: l10n.text('admin.alternate'))),
                if (error != null) Text(error!,
                    key: const Key('admin-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.text('common.cancel'))),
              FilledButton(
                key: const Key('admin-save'),
                onPressed: () {
                  if (selected == null) {
                    update(() => error = l10n.text('admin.parentRequired'));
                    return;
                  }
                  Navigator.pop(dialogContext, _AdministrativeAreaDraft(
                    level: level, parentId: selected, name: name,
                    code: code, alternate: alternate,
                  ));
                },
                child: Text(l10n.text('common.save')),
              ),
            ],
          );
        },
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.catalog.add(
        subject: widget.subject, level: draft.level,
        parentId: draft.parentId, name: draft.name,
        code: draft.code, alternateName: draft.alternate,
      );
      final refreshed = await widget.catalog.all();
      if (mounted) {
        setState(() => units = refreshed);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.text('admin.saveFailed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('admin.title'))),
      body: Builder(
        builder: (context) {
          if (loadError != null) {
            return Center(child: Text(l10n.text('admin.loadFailed')));
          }
          final all = units;
          if (all == null) {
            return const Center(child: CircularProgressIndicator());
          }
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
        onPressed: units == null ? null : () => _add(units!),
        icon: const Icon(Icons.add),
        label: Text(l10n.text('admin.add')),
      ),
    );
  }
}

class _AdministrativeAreaDraft {
  const _AdministrativeAreaDraft({
    required this.level, required this.parentId, required this.name,
    required this.code, required this.alternate,
  });
  final AdministrativeLevel level;
  final String parentId;
  final String name;
  final String code;
  final String alternate;
}
