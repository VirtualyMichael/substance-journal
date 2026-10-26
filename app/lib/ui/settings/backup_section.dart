import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/backup.dart';
import '../../data/database.dart';
import '../../data/sync.dart';
import '../../providers.dart';
import '../design.dart';

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider), ref.watch(syncServiceProvider)),
);

String _today() {
  final t = DateTime.now();
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Settings block for encrypted backups, restoring them, plain exports and the automatic copies.
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Backup and export', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'An encrypted backup is one file protected by a passphrase you choose. Keep it anywhere; without the passphrase nobody can read it, '
          'including you, so do not lose it. Restoring merges a backup in and never removes newer entries.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
          FilledButton.icon(
            key: const ValueKey('create-backup'),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Create encrypted backup'),
            onPressed: () => _create(context, ref),
          ),
          OutlinedButton.icon(
            key: const ValueKey('restore-backup'),
            icon: const Icon(Icons.restore),
            label: const Text('Restore a backup'),
            onPressed: () => _restore(context, ref),
          ),
        ]),
        const SizedBox(height: Gap.md),
        Text('Plain exports (not encrypted)', style: text.titleSmall),
        const SizedBox(height: 4),
        Text('Your doses as a spreadsheet, or everything as JSON. Anyone with the file can read it.', style: text.bodySmall),
        const SizedBox(height: Gap.sm),
        Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
          OutlinedButton.icon(
            key: const ValueKey('export-csv'),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Export CSV'),
            onPressed: () => _export(context, ref, 'csv'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('export-json'),
            icon: const Icon(Icons.data_object),
            label: const Text('Export JSON'),
            onPressed: () => _export(context, ref, 'json'),
          ),
        ]),
        const SizedBox(height: Gap.md),
        const _AutomaticCopies(),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, String kind) async {
    final service = ref.read(backupServiceProvider);
    final content = kind == 'csv' ? await service.exportCsv() : await service.exportJson();
    if (!context.mounted) return;
    await _output(context, ref, 'substance-journal-${_today()}.$kind', content, kind == 'csv' ? 'CSV export' : 'JSON export');
  }

  Future<String?> _passphrase(BuildContext context, {required bool confirm, required String title}) {
    final first = TextEditingController();
    final second = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('passphrase'),
                  controller: first,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Passphrase'),
                ),
                if (confirm)
                  TextField(
                    key: const ValueKey('passphrase-again'),
                    controller: second,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Passphrase again'),
                  ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: Gap.sm), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                key: const ValueKey('passphrase-ok'),
                onPressed: () {
                  if (first.text.length < 6) return setState(() => error = 'Use at least 6 characters.');
                  if (confirm && first.text != second.text) return setState(() => error = 'The two passphrases differ.');
                  Navigator.pop(context, first.text);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _busy(BuildContext context, String label) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: Gap.md), Text(label)])),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final pass = await _passphrase(context, confirm: true, title: 'Choose a passphrase');
    if (pass == null || !context.mounted) return;
    _busy(context, 'Encrypting...');
    String? backup;
    Object? failure;
    try {
      backup = await ref.read(backupServiceProvider).createEncryptedBackup(pass);
    } catch (e) {
      failure = e;
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (backup == null) return _info(context, 'Backup failed', '$failure');
    await _output(context, ref, 'substance-journal-${_today()}.sjbak', backup, 'Encrypted backup');
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final text = await ref.read(packageFilePickerProvider)();
    if (text == null || !context.mounted) return;
    if (!looksLikeBackup(text)) return _info(context, 'Not a backup', 'That file is not a Substance Journal backup (.sjbak).');
    final pass = await _passphrase(context, confirm: false, title: 'Backup passphrase');
    if (pass == null || !context.mounted) return;
    _busy(context, 'Decrypting...');
    ApplyResult? result;
    String? problem;
    try {
      result = await ref.read(backupServiceProvider).restoreEncryptedBackup(text, pass);
    } on SyncCryptoException catch (e) {
      problem = e.message;
    } on SyncException catch (e) {
      problem = e.message;
    } catch (e) {
      problem = 'Could not restore: $e';
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (result == null) return _info(context, 'Could not restore', problem ?? 'Unknown problem.');
    await _info(
      context,
      'Backup restored',
      result.applied == 0
          ? 'Everything in the backup was already here.'
          : '${result.applied} entries restored. ${result.skipped} were already here or newer.',
    );
  }

  Future<void> _info(BuildContext context, String title, String body) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body, key: const ValueKey('backup-message')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  /// Offers save / share / copy for generated text.
  Future<void> _output(BuildContext context, WidgetRef ref, String fileName, String content, String title) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$title ready', style: Theme.of(context).textTheme.titleMedium),
              Text('$fileName, ${(content.length / 1024).toStringAsFixed(0)} KB', key: const ValueKey('output-summary')),
              const SizedBox(height: Gap.sm),
              Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                FilledButton.icon(
                  key: const ValueKey('output-save'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save file'),
                  onPressed: () async {
                    final saved = await ref.read(packageSaverProvider)(fileName, content);
                    if (saved != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $saved')));
                    }
                  },
                ),
                OutlinedButton.icon(
                  key: const ValueKey('output-share'),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  onPressed: () => ref.read(packageSharerProvider)(fileName, content),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('output-copy'),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutomaticCopies extends StatelessWidget {
  const _AutomaticCopies();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<Directory>(
      future: defaultDatabaseFile().then(BackupService.folderFor),
      builder: (context, snapshot) {
        final folder = snapshot.data;
        final copies = folder == null ? const <File>[] : BackupService.listCopies(folder);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Automatic copies', style: text.titleSmall),
            const SizedBox(height: 4),
            Text(
              folder == null
                  ? 'Checking...'
                  : copies.isEmpty
                      ? 'A copy of the database is kept here once a day, and before an update changes its format.'
                      : '${copies.length} kept on this device, newest ${formatDate(copies.first.lastModifiedSync())}. '
                          'A copy is made daily (the last 14 are kept) and before an update changes the database format.',
              key: const ValueKey('auto-copies'),
              style: text.bodySmall,
            ),
            if (folder != null) SelectableText(folder.path, style: text.bodySmall),
          ],
        );
      },
    );
  }
}
