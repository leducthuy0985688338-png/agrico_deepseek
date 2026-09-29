import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/land_parcel.dart';

class BoundaryHistoryScreen extends StatelessWidget {
  const BoundaryHistoryScreen({super.key, required this.history});
  final List<LandParcelBoundaryVersion> history;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('boundary.history.title'))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: history.length,
        itemBuilder: (_, index) {
          final value = history[index];
          return Card(
            child: ListTile(
              key: Key('boundary-version-${value.version}'),
              title: Text('${l10n.text('boundary.version')} ${value.version}'),
              subtitle: Text(
                [
                  value.occurredAt.toLocal().toString(),
                  value.actorMembershipId,
                  l10n.text('boundary.source.${value.source.name}'),
                  '${value.areaM2.toStringAsFixed(1)} m² · ${value.perimeterM.toStringAsFixed(1)} m',
                  if (value.horizontalAccuracyM != null)
                    '±${value.horizontalAccuracyM!.toStringAsFixed(1)} m',
                  if (value.boundaryConfidence != null)
                    '${(value.boundaryConfidence! * 100).toStringAsFixed(0)}%',
                  l10n.text('verification.${value.verificationStatus.name}'),
                  if (value.note != null) value.note!,
                  if (value.sourceFileName != null) value.sourceFileName!,
                ].join('\n'),
              ),
            ),
          );
        },
      ),
    );
  }
}
