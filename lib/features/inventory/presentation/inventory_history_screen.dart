import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../application/inventory_service.dart';
import '../domain/entities/inventory_item.dart';

class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({
    super.key,
    required this.subject,
    required this.service,
  });
  final AuthorizationSubject subject;
  final InventoryService service;

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  late Future<(List<InventoryItem>, List<InventoryMovement>)> data;

  Future<(List<InventoryItem>, List<InventoryMovement>)> load() async {
    final items = await widget.service.list(widget.subject);
    final movements = await widget.service.movements(widget.subject);
    final sorted = [...movements]
      ..sort((a, b) {
        final date = b.occurredAt.compareTo(a.occurredAt);
        return date != 0 ? date : b.id.compareTo(a.id);
      });
    return (items, sorted);
  }

  @override
  void initState() {
    super.initState();
    data = load();
  }

  void reload() {
    setState(() {
      data = load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('inventory.history')),
        actions: [
          IconButton(
            key: const Key('inventory-history-refresh'),
            onPressed: reload,
            tooltip: l10n.text('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<(List<InventoryItem>, List<InventoryMovement>)>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('inventory.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (items, movements) = snapshot.data!;
          if (movements.isEmpty) {
            return Center(child: Text(l10n.text('common.empty')));
          }
          final byId = {for (final item in items) item.id: item};
          return ListView.builder(
            itemCount: movements.length,
            itemBuilder: (context, index) {
              final movement = movements[index];
              final item = byId[movement.itemId];
              final date = movement.occurredAt.toUtc().add(
                const Duration(hours: 7),
              );
              String two(int value) => value.toString().padLeft(2, '0');
              final stamp =
                  '${two(date.day)}/${two(date.month)}/${date.year} '
                  '${two(date.hour)}:${two(date.minute)} (UTC+7)';
              final receipt = movement.kind == InventoryMovementKind.receipt;
              return ListTile(
                key: Key('inventory-history-${movement.id}'),
                leading: Icon(
                  receipt ? Icons.arrow_downward : Icons.arrow_upward,
                ),
                title: Text(
                  movement.code ?? l10n.text('inventory.noDocumentCode'),
                ),
                subtitle: Text(
                  '${item == null ? movement.itemId : '${item.code} · ${item.name}'}\n'
                  '${l10n.text('inventory.${movement.kind.name}')}: '
                  '${movement.quantity} ${item?.unit ?? ''}\n$stamp',
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
