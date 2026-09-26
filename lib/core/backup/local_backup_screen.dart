import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/production_cost_database.dart';
import '../localization/app_localizations.dart';
import 'local_database_snapshot.dart';
import 'local_restore_preflight.dart';

class LocalBackupScreen extends StatefulWidget {
  const LocalBackupScreen({super.key, required this.database});
  final Database database;

  @override
  State<LocalBackupScreen> createState() => _LocalBackupScreenState();
}

class _LocalBackupScreenState extends State<LocalBackupScreen> {
  bool busy = false;
  Map<String, int>? preview;
  String? error;
  String? errorDatabase;
  bool preflightPassed = false;

  Future<void> _export() async {
    setState(() { busy = true; error = null; });
    try {
      final costs = await ProductionCostDatabase().database;
      final bytes = await LocalDatabaseSnapshot.create(
        widget.database, costsDatabase: costs,
      );
      final now = DateTime.now().toUtc();
      final date = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'AGRICO', fileName: 'AGRICO-$date.json', bytes: bytes,
      );
      if (destination != null && mounted) {
        setState(() { preview = LocalDatabaseSnapshot.inspect(bytes); preflightPassed = false; });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'backup.exportFailed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _inspect() async {
    setState(() { busy = true; error = null; });
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true,
      );
      if (selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) throw const FormatException('Cannot read backup.');
      final counts = LocalDatabaseSnapshot.inspect(Uint8List.fromList(bytes));
      if (mounted) setState(() { preview = counts; preflightPassed = false; });
    } catch (_) {
      if (mounted) setState(() => error = 'backup.invalid');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _preflight() async {
    setState(() { busy = true; error = null; errorDatabase = null; preview = null; });
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true,
      );
      if (selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) throw const FormatException('Cannot read backup.');
      final costs = await ProductionCostDatabase().database;
      final temporary = await getTemporaryDirectory();
      final counts = await LocalRestorePreflight.validate(
        bytes: Uint8List.fromList(bytes),
        primary: widget.database,
        costs: costs,
        factory: databaseFactory,
        temporaryDirectory: temporary.path,
      );
      if (mounted) setState(() { preview = counts; preflightPassed = true; });
    } on RestorePreflightException catch (failure) {
      if (mounted) setState(() {
        error = 'backup.preflight.${failure.reason}';
        errorDatabase = failure.database;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'backup.preflightFailed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('backup.title'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(l10n.text('backup.explanation')),
        const SizedBox(height: 12),
        Text(l10n.text('backup.externalFiles')),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : _export,
          icon: const Icon(Icons.save_alt),
          label: Text(l10n.text('backup.export')),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : _inspect,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(l10n.text('backup.inspect')),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : _preflight,
          icon: const Icon(Icons.verified_outlined),
          label: Text(l10n.text('backup.preflight')),
        ),
        if (busy) const Center(child: CircularProgressIndicator()),
        if (error != null) Text('${l10n.text(error!)}${errorDatabase == null ? '' : ' ($errorDatabase)'}',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (preview != null) ...[
          Text(l10n.text(preflightPassed ? 'backup.preflightValid' : 'backup.valid')),
          for (final entry in preview!.entries)
            ListTile(title: Text(entry.key), trailing: Text('${entry.value}')),
        ],
      ]),
    );
  }
}
