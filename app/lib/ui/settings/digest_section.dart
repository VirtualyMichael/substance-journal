import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/digest.dart';
import '../../data/digest_service.dart';
import '../../providers.dart';
import '../design.dart';
import '../toast.dart';

/// A text summary of the journal for an AI: copied to paste into a chat, or kept up to date as a
/// folder of small files a local AI can read piece by piece.
class DigestSection extends ConsumerStatefulWidget {
  const DigestSection({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<DigestSection> createState() => _DigestSectionState();
}

class _DigestSectionState extends ConsumerState<DigestSection> {
  SummarySize _size = SummarySize.medium;
  bool _private = true;
  bool _busy = false;
  String? _message;
  bool _auto = false;
  String _folder = '';

  bool get _desktop => !(Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final auto = await db.getSetting('digestAuto') == 'true';
    final saved = await db.getSetting('digestFolder');
    var folder = saved ?? '';
    if (folder.isEmpty) {
      try {
        folder = (await defaultDigestFolder()).path;
      } on Object {
        // No documents folder on this platform; the person can choose one.
      }
    }
    if (mounted) {
      setState(() {
        _auto = auto;
        _folder = folder;
      });
    }
  }

  Future<void> _deleteFiles() async {
    final n = deleteDigestFiles(Directory(_folder));
    if (mounted) setState(() => _message = n == 0 ? 'Nothing to delete in that folder.' : 'Deleted the files for $n ${n == 1 ? 'person' : 'people'}.');
  }

  Future<void> _copy() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final digest = await buildDigestForPerson(
        ref.read(databaseProvider),
        widget.person,
        ref.read(catalogProvider).byKey,
        ref.read(clockProvider)(),
        options: _private ? DigestOptions.private : DigestOptions.full,
      );
      final text = composeSummary(digest, _size);
      await Clipboard.setData(ClipboardData(text: text));
      setState(() => _message = 'Copied about ${estimateTokens(text)} tokens. Paste it into your AI.');
    } on Object catch (e) {
      setState(() => _message = 'Could not make the summary: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final count = await writeDigestFolder(Directory(_folder), ref.read(databaseProvider), ref.read(catalogProvider).byKey, ref.read(clockProvider)());
      setState(() => _message = 'Wrote $count files to $_folder');
    } on Object catch (e) {
      setState(() => _message = 'Could not write the folder: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Folder for the AI digest');
    if (path == null) return;
    await ref.read(databaseProvider).setSetting('digestFolder', path);
    setState(() => _folder = path);
  }

  Future<void> _setAuto(bool on) async {
    await ref.read(databaseProvider).setSetting('digestAuto', on ? 'true' : 'false');
    setState(() => _auto = on);
    if (on) {
      await _write();
      if (mounted) {
        ScaffoldMessenger.of(context).showToast(const SnackBar(content: Text('The digest folder is plain text. Anyone with access to this computer can read it.')), important: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Summary for an AI', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          "A summary of ${widget.person.name}'s journal for a local or cloud AI: every dose with potency, the estimated curve, notes, ratings and tolerance, calculated here so the AI only has to explain it. "
          'A cloud AI sees whatever you paste.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        SegmentedButton<SummarySize>(
          key: const ValueKey('digest-size'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: SummarySize.small, label: Text('Small')),
            ButtonSegment(value: SummarySize.medium, label: Text('Medium')),
            ButtonSegment(value: SummarySize.large, label: Text('Large')),
          ],
          selected: {_size},
          onSelectionChanged: (v) => setState(() => _size = v.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            switch (_size) {
              SummarySize.small => 'About 0.5k tokens: the profile (what is used, how often, tolerance, last week).',
              SummarySize.medium => 'About 1.5k tokens: the profile and this month day by day.',
              SummarySize.large => 'About 4-8k tokens: the profile, this month and the five latest experiences in detail.',
            },
            style: text.bodySmall,
          ),
        ),
        SwitchListTile(
          key: const ValueKey('digest-private'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Leave out names, notes and places'),
          subtitle: const Text('Recommended before pasting into a cloud AI.'),
          value: _private,
          onChanged: (v) => setState(() => _private = v),
        ),
        FilledButton.icon(
          key: const ValueKey('digest-copy'),
          icon: const Icon(Icons.copy),
          label: const Text('Copy summary'),
          onPressed: _busy ? null : _copy,
        ),
        if (_desktop) ...[
          const Divider(height: Gap.lg * 2),
          Text('Folder for a local AI', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Keeps small files up to date (a profile, a page per month, a sheet per experience) that an AI tool reads one piece at a time, so it never needs the whole log. '
            'Includes names and notes as written. These files are plain text: the app lock and the journal encryption do not cover them.',
            style: text.bodySmall,
          ),
          SwitchListTile(
            key: const ValueKey('digest-auto'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep the folder up to date'),
            subtitle: Text(_folder),
            value: _auto,
            onChanged: _busy ? null : _setAuto,
          ),
          Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
            OutlinedButton.icon(key: const ValueKey('digest-write'), icon: const Icon(Icons.folder_outlined), label: const Text('Write now'), onPressed: _busy ? null : _write),
            TextButton(key: const ValueKey('digest-delete'), onPressed: _busy ? null : _deleteFiles, child: const Text('Delete these files')),
            TextButton(key: const ValueKey('digest-folder'), onPressed: _busy ? null : _chooseFolder, child: const Text('Choose folder')),
          ]),
        ],
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_message!, key: const ValueKey('digest-message'), style: text.bodySmall)),
      ],
    );
  }
}
