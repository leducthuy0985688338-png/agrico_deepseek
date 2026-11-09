import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../application/production_history_service.dart';
import '../../domain/entities/land_parcel.dart';

class ProductionHistoryScreen extends StatefulWidget {
  const ProductionHistoryScreen({
    super.key,
    required this.service,
    required this.openParcel,
  });
  final ProductionHistoryService service;
  final void Function(LandParcel) openParcel;

  @override
  State<ProductionHistoryScreen> createState() =>
      _ProductionHistoryScreenState();
}

class _ProductionHistoryScreenState extends State<ProductionHistoryScreen> {
  late Future<List<LandParcel>> data = widget.service.listParcels();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.productionLogs')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.text('common.retry'),
            onPressed: () {
              setState(() {
                data = widget.service.listParcels();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<LandParcel>>(
        future: data,
        builder: (context, snapshot) {
          if (!widget.service.canView || snapshot.hasError) {
            return Center(child: Text(l10n.text('work.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final parcels = snapshot.data!;
          if (parcels.isEmpty) {
            return Center(child: Text(l10n.text('common.empty')));
          }
          return ListView.builder(
            itemCount: parcels.length,
            itemBuilder: (context, index) {
              final parcel = parcels[index];
              return ListTile(
                key: Key('production-history-${parcel.id}'),
                title: Text(parcel.name),
                subtitle: Text(parcel.parcelCode),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (widget.service.canView) {
                    widget.openParcel(parcel);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
