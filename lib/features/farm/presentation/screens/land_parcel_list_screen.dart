import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/land_parcel_boundary_consistency_queries.dart';
import '../../domain/entities/land_parcel.dart';
import '../controllers/land_parcel_controller.dart';
import 'land_parcel_detail_screen.dart';

class LandParcelListScreen extends StatefulWidget {
  const LandParcelListScreen({
    super.key,
    required this.controller,
    this.onCreate,
    this.detailBuilder,
  });
  final LandParcelController controller;
  final VoidCallback? onCreate;
  final Widget Function(BuildContext context, String parcelId)? detailBuilder;

  @override
  State<LandParcelListScreen> createState() => _LandParcelListScreenState();
}

class _LandParcelListScreenState extends State<LandParcelListScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.loadList();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('parcel.list.title'))),
      floatingActionButton: controller.can(PermissionCodes.fieldCreate)
          ? FloatingActionButton.extended(
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add),
              label: Text(l10n.text('parcel.create.action')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: controller.loadList,
        child: _body(context, controller, l10n),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    LandParcelController controller,
    AppLocalizations l10n,
  ) {
    if (controller.phase == ParcelPresentationPhase.loading ||
        controller.phase == ParcelPresentationPhase.initial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.phase == ParcelPresentationPhase.persistenceError) {
      return ListView(
        children: [
          const SizedBox(height: 160),
          Center(
            child: Text(
              l10n.text(controller.messageKey ?? 'parcel.list.error'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: controller.loadList,
              child: Text(l10n.text('common.retry')),
            ),
          ),
        ],
      );
    }
    final items = controller.visibleItems;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('parcel-search'),
          onChanged: controller.setSearch,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: l10n.text('parcel.search'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            DropdownButton<bool?>(
              value: controller.activeFilter,
              hint: Text(l10n.text('parcel.filter.active')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.text('common.all')),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text(l10n.text('common.active')),
                ),
                DropdownMenuItem(
                  value: false,
                  child: Text(l10n.text('common.inactive')),
                ),
              ],
              onChanged: controller.setActiveFilter,
            ),
            DropdownButton<BoundaryVerificationStatus?>(
              value: controller.verificationFilter,
              hint: Text(l10n.text('parcel.filter.verification')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.text('common.all')),
                ),
                ...BoundaryVerificationStatus.values.map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(l10n.text('verification.${value.name}')),
                  ),
                ),
              ],
              onChanged: controller.setVerificationFilter,
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l10n.text('boundary.audit.visibleSummary')),
          Wrap(
            spacing: 8,
            children: [
              for (final status in LandParcelBoundaryConsistency.values)
                Chip(
                  key: Key('boundary-audit-${status.name}'),
                  label: Text(
                    '${l10n.text('boundary.audit.${status.name}')}: '
                    '${items.where((item) => item.boundaryConsistency == status).length}',
                  ),
                ),
            ],
          ),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 96),
            child: Center(child: Text(l10n.text('parcel.list.empty'))),
          )
        else
          ...items.map(
            (item) => Card(
              child: ListTile(
                key: Key('parcel-${item.parcel.id}'),
                title: Text('${item.parcel.parcelCode} · ${item.parcel.name}'),
                subtitle: Text(
                  [
                    if (item.village.isNotEmpty) item.village,
                    if (item.owner.isNotEmpty) item.owner,
                    '${item.parcel.areaHa.toStringAsFixed(2)} ha',
                    l10n.text(
                      'verification.${item.parcel.verificationStatus.name}',
                    ),
                    l10n.text(
                      'boundary.audit.${item.boundaryConsistency.name}',
                    ),
                    if (item.cropSummary.isNotEmpty) item.cropSummary,
                  ].join(' · '),
                ),
                trailing: Icon(
                  item.parcel.active ? Icons.check_circle : Icons.pause_circle,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (routeContext) =>
                        widget.detailBuilder?.call(
                          routeContext,
                          item.parcel.id,
                        ) ??
                        LandParcelDetailScreen(
                          controller: controller,
                          parcelId: item.parcel.id,
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
