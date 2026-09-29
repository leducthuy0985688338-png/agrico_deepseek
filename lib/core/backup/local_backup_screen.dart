import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/production_cost_database.dart';
import '../localization/app_localizations.dart';
import 'local_database_snapshot.dart';
import 'local_encrypted_backup.dart';
import 'local_media_snapshot.dart';
import 'local_restore_activation.dart';
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
  String? errorStep;
  bool preflightPassed = false;
  Uint8List? validatedBackup;
  bool restoreScheduled = false;
  String? restoreStatus;
  bool legacyUnencrypted = false;

  @override
  void initState() {
    super.initState();
    localRestoreStatus().then((status) {
      if (mounted) setState(() => restoreStatus = status);
    });
  }

  Future<void> _export() async {
    setState(() { busy = true; error = null; validatedBackup = null; preflightPassed = false; legacyUnencrypted = false; });
    try {
      final password = await _newPassword();
      if (password == null) return;
      final costs = await ProductionCostDatabase().database;
      final bytes = await LocalMediaSnapshot.create(widget.database, costs);
      final encrypted = await LocalEncryptedBackup.encrypt(bytes, password);
      final now = DateTime.now().toUtc();
      final date = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'AGRICO', fileName: 'AGRICO-$date.agrico', bytes: encrypted,
      );
      if (destination != null && mounted) {
        setState(() { preview = LocalDatabaseSnapshot.inspect(bytes); preflightPassed = false; legacyUnencrypted = false; });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'backup.exportFailed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _inspect() async {
    setState(() { busy = true; error = null; validatedBackup = null; preflightPassed = false; legacyUnencrypted = false; });
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json', 'agrico'], withData: true,
      );
      if (selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) throw const FormatException('Cannot read backup.');
      final plain = await _readSelected(Uint8List.fromList(bytes));
      if (plain == null) return;
      LocalMediaSnapshot.validate(plain);
      final counts = LocalDatabaseSnapshot.inspect(plain);
      if (mounted) setState(() { preview = counts; preflightPassed = false; });
      if (legacyUnencrypted) await _showLegacyWarning();
    } on BackupPasswordException {
      if (mounted) setState(() => error = 'backup.passwordInvalid');
    } catch (_) {
      if (mounted) setState(() => error = 'backup.invalid');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _preflight() async {
    setState(() { busy = true; error = null; errorDatabase = null; errorStep = null; preview = null; validatedBackup = null; preflightPassed = false; legacyUnencrypted = false; });
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json', 'agrico'], withData: true,
      );
      if (selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) throw const FormatException('Cannot read backup.');
      final plain = await _readSelected(Uint8List.fromList(bytes));
      if (plain == null) return;
      await _validateRestoreBytes(plain);
      if (legacyUnencrypted) await _showLegacyWarning();
    } on BackupPasswordException {
      if (mounted) setState(() => error = 'backup.passwordInvalid');
    } on RestorePreflightException catch (failure) {
      if (mounted) {
        setState(() {
          error = 'backup.preflight.${failure.reason}';
          errorDatabase = failure.database;
          errorStep = failure.step;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'backup.preflightFailed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadPrevious() async {
    setState(() { busy = true; error = null; preview = null;
      validatedBackup = null; preflightPassed = false; legacyUnencrypted = false; });
    try {
      final bytes = await previousLocalRestoreBackup();
      if (bytes == null) throw const FormatException('No previous backup.');
      await _validateRestoreBytes(bytes);
      if (mounted) setState(() => legacyUnencrypted = false);
    } on RestorePreflightException catch (failure) {
      if (mounted) {
        setState(() {
          error = 'backup.preflight.${failure.reason}';
          errorDatabase = failure.database;
          errorStep = failure.step;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'backup.preflightFailed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Uint8List?> _readSelected(Uint8List bytes) async {
    final encrypted = LocalEncryptedBackup.isEncrypted(bytes);
    if (mounted) setState(() => legacyUnencrypted = !encrypted);
    if (!encrypted) return bytes;
    final password = await _enterPassword();
    if (password == null) return null;
    return LocalEncryptedBackup.decrypt(bytes, password);
  }

  Future<String?> _enterPassword() => showDialog<String>(
    context: context,
    builder: (_) => const _BackupPasswordDialog(),
  );

  Future<String?> _newPassword() => showDialog<String>(
    context: context,
    builder: (_) => const _BackupPasswordDialog(confirm: true),
  );

  Future<void> _showLegacyWarning() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.text('backup.legacyTitle')),
        content: Text(l10n.text('backup.legacyUnencrypted')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.text('common.confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _validateRestoreBytes(Uint8List bytes) async {
    LocalMediaSnapshot.validate(bytes);
    final costs = await ProductionCostDatabase().database;
    final temporary = await getTemporaryDirectory();
    final counts = await LocalRestorePreflight.validate(
      bytes: bytes,
      primary: widget.database,
      costs: costs,
      factory: databaseFactory,
      temporaryDirectory: temporary.path,
    );
    if (mounted) {
      setState(() {
        preview = counts;
        validatedBackup = bytes;
        preflightPassed = true;
      });
    }
  }

  Future<void> _scheduleRestore() async {
    final bytes = validatedBackup;
    if (bytes == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.text('backup.applyTitle')),
        content: Text(l10n.text('backup.applyWarning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.text('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.text('backup.applyConfirm'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try {
      await scheduleLocalRestore(bytes);
      if (mounted) setState(() => restoreScheduled = true);
    } catch (_) {
      if (mounted) setState(() => error = 'backup.applyFailed');
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
        if (legacyUnencrypted) Text(l10n.text('backup.legacyUnencrypted')),
        if (restoreStatus == 'applied') Text(l10n.text('backup.applied')),
        if (restoreStatus == 'failed') Text(l10n.text('backup.applyFailed')),
        if (restoreScheduled) Text(l10n.text('backup.scheduled')),
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
        if (restoreStatus == 'applied')
          OutlinedButton.icon(
            onPressed: busy ? null : _loadPrevious,
            icon: const Icon(Icons.history),
            label: Text(l10n.text('backup.previous')),
          ),
        if (preflightPassed && !restoreScheduled)
          FilledButton.icon(
            onPressed: busy ? null : _scheduleRestore,
            icon: const Icon(Icons.restore),
            label: Text(l10n.text('backup.apply')),
          ),
        if (busy) const Center(child: CircularProgressIndicator()),
        if (error != null) Text('${l10n.text(error!)}${errorDatabase == null ? '' : ' ($errorDatabase)'}${errorStep == null ? '' : ' [$errorStep]'}',
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

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({this.confirm = false});
  final bool confirm;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final first = TextEditingController();
  final second = TextEditingController();

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allowed = widget.confirm
        ? first.text.runes.length >= 12 && first.text == second.text
        : first.text.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.text(widget.confirm
          ? 'backup.newPasswordTitle' : 'backup.passwordTitle')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.confirm) Text(l10n.text('backup.passwordAdvice')),
        TextField(
          controller: first,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.text('backup.password')),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.confirm) TextField(
          controller: second,
          obscureText: true,
          decoration: InputDecoration(
              labelText: l10n.text('backup.confirmPassword')),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.text('common.cancel')),
        ),
        FilledButton(
          onPressed: allowed ? () => Navigator.pop(context, first.text) : null,
          child: Text(l10n.text(widget.confirm
              ? 'backup.export' : 'common.confirm')),
        ),
      ],
    );
  }
}
