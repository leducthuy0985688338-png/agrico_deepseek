import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_work_service.dart';
import '../../domain/entities/parcel_work.dart';

/// Farm resource catalog shared with the parcel clearing/cultivation workflow.
class WorkResourceCatalogScreen extends StatefulWidget {
  const WorkResourceCatalogScreen({
    super.key,
    required this.kind,
    required this.subject,
    required this.service,
  });

  final WorkResourceKind kind;
  final AuthorizationSubject subject;
  final ParcelWorkService service;

  @override
  State<WorkResourceCatalogScreen> createState() =>
      _WorkResourceCatalogScreenState();
}

class _WorkResourceCatalogScreenState extends State<WorkResourceCatalogScreen> {
  late Future<List<WorkResource>> resources;

  @override
  void initState() {
    super.initState();
    resources = widget.service.resources(widget.subject);
  }

  void reload() => setState(() {
    resources = widget.service.resources(widget.subject);
  });

  Future<void> addResource() async {
    final l10n = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.text('work.${widget.kind.name}')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('catalog-code'),
              controller: code,
              decoration: InputDecoration(labelText: l10n.text('work.code')),
            ),
            TextField(
              key: const Key('catalog-name'),
              controller: name,
              decoration: InputDecoration(labelText: l10n.text('work.name')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('catalog-save'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.text('common.save')),
          ),
        ],
      ),
    );
    final submitted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    await route.completed;
    if (submitted == true) {
      try {
        await widget.service.register(
          widget.subject,
          WorkResource(
            id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
            farmId: widget.subject.farmId,
            kind: widget.kind,
            code: code.text.trim(),
            name: name.text.trim(),
          ),
        );
        if (mounted) reload();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.text('work.saveFailed'))));
        }
      }
    }
    code.dispose();
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canEdit = const AuthorizationService().can(
      subject: widget.subject,
      permission: PermissionCodes.catalogManage,
      resource: ResourceContext(farmId: widget.subject.farmId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('work.${widget.kind.name}')),
        actions: [
          IconButton(
            onPressed: reload,
            tooltip: l10n.text('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              key: const Key('catalog-add'),
              onPressed: addResource,
              tooltip: l10n.text('work.addResource'),
              child: const Icon(Icons.add),
            )
          : null,
      body: FutureBuilder<List<WorkResource>>(
        future: resources,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('work.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final matching = snapshot.data!
              .where((resource) => resource.kind == widget.kind)
              .toList(growable: false);
          return ListView.builder(
            key: const Key('catalog-resources'),
            itemCount: matching.length,
            itemBuilder: (context, index) {
              final resource = matching[index];
              return ListTile(
                title: Text(resource.name),
                subtitle: Text(resource.code),
                enabled: resource.active,
              );
            },
          );
        },
      ),
    );
  }
}
