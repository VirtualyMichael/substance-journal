import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/dedupe.dart';
import '../../data/lan_sync.dart';
import '../../data/sync.dart';
import '../../providers.dart';
import '../design.dart';
import 'qr_widgets.dart';

/// Sync with your other devices without any server or connection.
///
/// Pair once (scan a code, or paste it). After that, "Send" makes a sealed package of what
/// changed. It can be shown as QR codes, saved as a file, shared, or copied as text and sent
/// through anything (a message, an email, a command). "Receive" takes one in by camera, paste or
/// file. Everything is encrypted with the key you share when pairing.
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  List<SyncPeer> _peers = const [];
  bool _loaded = false;
  bool _wifiBusy = false;
  List<String> _addresses = const [];
  bool _canUndoCleanup = false;

  SyncService get _sync => ref.read(syncServiceProvider);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final peers = await _sync.peers();
    final undo = await DuplicateCleaner(ref.read(databaseProvider)).hasUndo();
    final addresses = await LanSyncClient.localAddresses();
    if (!mounted) return;
    setState(() {
      _peers = peers;
      _loaded = true;
      _canUndoCleanup = undo;
      _addresses = addresses;
    });
  }

  /// Syncs with one paired device over the network, or with every paired device.
  Future<void> _wifiSync({SyncPeer? only, String? address}) async {
    final targets = only != null ? [only] : [for (final p in _peers) if (!p.pending) p];
    if (targets.isEmpty) return _message('Pair with a device first, and start the first sync from the device that scanned the code.');
    setState(() => _wifiBusy = true);
    final lines = <String>[];
    try {
      final client = ref.read(lanClientProvider);
      for (final peer in targets) {
        try {
          final host = address?.split(':').first;
          final port = address != null && address.contains(':') ? int.tryParse(address.split(':').last) : null;
          final r = await client.syncWith(peer.deviceId, address: host, port: port);
          lines.add('${r.peerName}: ${r.received == 0 ? 'up to date' : '${r.received} changes merged'}');
        } on LanSyncException catch (e) {
          lines.add('${peer.name}: ${e.message}');
        } catch (e) {
          lines.add('${peer.name}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _wifiBusy = false);
    }
    await _refresh();
    _message(lines.join('\n'));
  }

  Future<void> _connectByAddress(SyncPeer peer) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connect to ${peer.name}'),
        content: TextField(
          key: const ValueKey('address-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Address', hintText: '192.168.1.20  or  192.168.1.20:47832'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Sync')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) await _wifiSync(only: peer, address: text);
  }

  Future<void> _findDuplicates({bool sameDay = false}) async {
    final cleaner = DuplicateCleaner(ref.read(databaseProvider));
    final scan = await cleaner.scan(combineNearby: sameDay);
    if (!mounted) return;
    if (scan.isEmpty) return _message('No duplicates found.');
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicates found'),
        content: Text(
          '${scan.doseCopies} doses are copies of another dose'
          '${scan.experienceMerges.isEmpty ? '' : ', spread over ${scan.experienceMerges.fold<int>(0, (n, g) => n + g.length)} experiences that will become ${scan.experienceGroups}'}'
          '${scan.noteCopies + scan.ratingCopies == 0 ? '' : ', plus ${scan.noteCopies + scan.ratingCopies} repeated notes or ratings'}.\n\n'
          'Nothing is lost: each kept entry gets any note, time or detail its copy had, experiences are combined with everything in them, '
          'and real twins (two identical drinks in one experience) are left alone. You can undo this afterwards.',
          key: const ValueKey('duplicates-summary'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('cleanup-go'), onPressed: () => Navigator.pop(context, true), child: const Text('Merge duplicates')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final result = await cleaner.apply(scan);
    await _refresh();
    _message('Merged ${result.dosesMerged} doses and ${result.experiencesMerged} experiences. Use "Undo last cleanup" to reverse it.');
  }

  Future<void> _undoCleanup() async {
    final n = await DuplicateCleaner(ref.read(databaseProvider)).undo();
    await _refresh();
    _message('Restored $n entries.');
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showMyCode() async {
    final PairingCode code;
    try {
      code = await _sync.offerPairing();
    } catch (e) {
      _message('Could not create a pairing code: $e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => _PairingCodeDialog(code: code.encode()));
    await _refresh();
  }

  Future<void> _enterCode({bool scan = false}) async {
    String? text;
    if (scan) {
      text = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => QrScanPage(
          title: 'Scan a pairing code',
          hint: 'Point the camera at the pairing code on your other device.',
          onText: (t) => PairingCode.decode(t) != null ? ScanDone(t) : 'That is not a pairing code.',
        ),
      ));
    } else {
      text = await _pasteDialog(title: 'Paste a pairing code', hint: 'SJPAIR1:...');
    }
    if (text == null || !mounted) return;
    try {
      final name = await _sync.acceptPairing(text);
      await _refresh();
      if (mounted) {
        _message('Paired with $name. Now send your changes there, or receive theirs.');
      }
    } on SyncException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('Could not pair: $e');
    }
  }

  Future<String?> _pasteDialog({required String title, required String hint}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('paste-field'),
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) controller.text = data!.text!;
            },
            child: const Text('Paste'),
          ),
          FilledButton(
            key: const ValueKey('paste-ok'),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _send(SyncPeer peer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SendSheet(peer: peer),
    );
    await _refresh();
  }

  Future<void> _receive() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ref.read(cameraScannerAvailableProvider))
              ListTile(
                key: const ValueKey('receive-scan'),
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan QR codes'),
                subtitle: const Text('From the other device\'s Send screen'),
                onTap: () => Navigator.pop(context, 'scan'),
              ),
            ListTile(
              key: const ValueKey('receive-paste'),
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste text'),
              subtitle: const Text('A package sent to you as text'),
              onTap: () => Navigator.pop(context, 'paste'),
            ),
            ListTile(
              key: const ValueKey('receive-file'),
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Open a file'),
              subtitle: const Text('A .sjsync file'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    String? text;
    switch (choice) {
      case 'scan':
        final assembler = FrameAssembler();
        text = await Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => QrScanPage(
            title: 'Scan sync codes',
            hint: 'Point the camera at the codes on your other device. Hold steady; they cycle.',
            onText: (t) {
              if (t.startsWith('SJSYNC1:')) return ScanDone(t);
              if (!assembler.add(t)) return 'That is not a sync code.';
              return assembler.isComplete
                  ? ScanDone(assembler.payload)
                  : 'Read ${assembler.received} of ${assembler.total} codes...';
            },
          ),
        ));
      case 'paste':
        text = await _pasteDialog(title: 'Paste a sync package', hint: 'SJSYNC1:...');
      case 'file':
        text = await ref.read(packageFilePickerProvider)();
    }
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final result = await _sync.receivePackage(text);
      await _refresh();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sync complete'),
            content: Text(
              result.applied == 0
                  ? 'Nothing new from ${result.peerName}. You are up to date.'
                  : '${result.applied} changes from ${result.peerName} merged. ${result.skipped} were already here.',
              key: const ValueKey('sync-result'),
            ),
            actions: [FilledButton(key: const ValueKey('sync-done'), onPressed: () => Navigator.pop(context), child: const Text('Done'))],
          ),
        );
      }
    } on SyncException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: ref.read(deviceNameProvider).value ?? defaultDeviceName());
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(key: const ValueKey('device-name-field'), controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await ref.read(databaseProvider).setSetting('deviceName', name);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = ref.watch(deviceNameProvider).value ?? defaultDeviceName();
    final canScan = ref.watch(cameraScannerAvailableProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync devices')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text(
                'Keep your phone and computer journals the same, with no account and no server. '
                'Pair the devices once, then pass changes between them as QR codes, a file, or text you send any way you like. '
                'Everything is encrypted with a key only your devices have.',
              ),
              const SizedBox(height: Gap.md),
              ListTile(
                key: const ValueKey('device-name'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.devices_outlined),
                title: const Text('This device'),
                subtitle: Text(name),
                trailing: TextButton(onPressed: _rename, child: const Text('Rename')),
              ),
              const SizedBox(height: Gap.sm),
              FilledButton.icon(
                key: const ValueKey('wifi-sync'),
                icon: _wifiBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi),
                label: const Text('Sync now over Wi-Fi'),
                onPressed: _wifiBusy ? null : () => _wifiSync(),
              ),
              const SizedBox(height: 4),
              Text(
                'Both devices need the app open on the same Wi-Fi. The first sync must be started from the device that scanned the pairing code.'
                '${_addresses.isEmpty ? '' : ' This device: ${_addresses.join(', ')}.'}',
                style: text.bodySmall,
              ),
              SwitchListTile(
                key: const ValueKey('auto-sync'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Sync automatically'),
                subtitle: const Text('When the app opens, every few minutes, and shortly after you log something, whenever a paired device is on the same Wi-Fi.'),
                value: ref.watch(autoSyncEnabledProvider).value ?? true,
                onChanged: (v) => ref.read(databaseProvider).setSetting('autoSync', v ? 'true' : 'false'),
              ),
              const Divider(),
              Text('Pair a device', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('Do this once. Show a code on one device and enter it on the other.', style: text.bodySmall),
              const SizedBox(height: Gap.sm),
              Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                FilledButton.icon(
                  key: const ValueKey('show-pairing'),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Show my pairing code'),
                  onPressed: _showMyCode,
                ),
                if (canScan)
                  OutlinedButton.icon(
                    key: const ValueKey('scan-pairing'),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan a code'),
                    onPressed: () => _enterCode(scan: true),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('paste-pairing'),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste a code'),
                  onPressed: _enterCode,
                ),
              ]),
              const SizedBox(height: Gap.lg),
              Text('Paired devices', style: text.titleMedium),
              const SizedBox(height: Gap.sm),
              if (_loaded && _peers.isEmpty) Text('None yet.', style: text.bodySmall, key: const ValueKey('no-peers')),
              for (final peer in _peers)
                Card(
                  key: ValueKey('peer-${peer.deviceId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(peer.name, style: text.titleSmall)),
                          PopupMenuButton<String>(
                            key: ValueKey('peer-menu-${peer.deviceId}'),
                            onSelected: (_) async {
                              await _sync.forgetPeer(peer.deviceId);
                              await _refresh();
                            },
                            itemBuilder: (_) => const [PopupMenuItem(value: 'forget', child: Text('Forget this device'))],
                          ),
                        ]),
                        Text(
                          peer.pending
                              ? 'Waiting for the other device to scan or enter your code.'
                              : peer.lastSync == null
                                  ? 'Paired. Not synced yet.'
                                  : 'Last synced ${relativeTime(peer.lastSync!, ref.read(clockProvider)())}.',
                          style: text.bodySmall,
                        ),
                        const SizedBox(height: Gap.sm),
                        Wrap(spacing: Gap.sm, children: [
                          if (!peer.pending) ...[
                            FilledButton.tonalIcon(
                              key: ValueKey('wifi-${peer.deviceId}'),
                              icon: const Icon(Icons.wifi),
                              label: const Text('Wi-Fi'),
                              onPressed: _wifiBusy ? null : () => _wifiSync(only: peer),
                            ),
                            TextButton(
                              key: ValueKey('address-${peer.deviceId}'),
                              onPressed: _wifiBusy ? null : () => _connectByAddress(peer),
                              child: const Text('By address'),
                            ),
                          ],
                          FilledButton.tonalIcon(
                            key: ValueKey('send-${peer.deviceId}'),
                            icon: const Icon(Icons.upload),
                            label: const Text('Send'),
                            onPressed: () => _send(peer),
                          ),
                          FilledButton.tonalIcon(
                            key: ValueKey('receive-${peer.deviceId}'),
                            icon: const Icon(Icons.download),
                            label: const Text('Receive'),
                            onPressed: _receive,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: Gap.lg),
              Text('Duplicates', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'If syncing made copies of the same doses (for example you imported the same history on both devices), '
                'this finds them and merges each set into one, keeping anything only one copy had.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Gap.sm),
              Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                OutlinedButton.icon(
                  key: const ValueKey('find-duplicates'),
                  icon: const Icon(Icons.content_copy),
                  label: const Text('Find and merge duplicates'),
                  onPressed: _findDuplicates,
                ),
                OutlinedButton.icon(
                  key: const ValueKey('combine-days'),
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Combine experiences on the same day'),
                  onPressed: () => _findDuplicates(sameDay: true),
                ),
                if (_canUndoCleanup)
                  OutlinedButton.icon(
                    key: const ValueKey('undo-cleanup'),
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo last cleanup'),
                    onPressed: _undoCleanup,
                  ),
              ]),
              const SizedBox(height: Gap.md),
              Text(
                'Tip: after pairing, send from one device, receive on the other, then send back. '
                'Each package only carries what the other device does not have yet.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairingCodeDialog extends StatelessWidget {
  const _PairingCodeDialog({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your pairing code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrCard(data: code),
            const SizedBox(height: Gap.sm),
            const Text('On your other device, choose "Scan a code". No camera? Copy the text instead.', textAlign: TextAlign.center),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              key: const ValueKey('copy-pairing'),
              icon: const Icon(Icons.copy),
              label: const Text('Copy code as text'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Keep it private: it is the key to your journal.')));
                }
              },
            ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}

/// Builds a package for one peer and offers every way of getting it across.
class _SendSheet extends ConsumerStatefulWidget {
  const _SendSheet({required this.peer});

  final SyncPeer peer;

  @override
  ConsumerState<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<_SendSheet> {
  bool _everything = false;
  String? _package;
  int? _changes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() {
      _package = null;
      _error = null;
    });
    try {
      final sync = ref.read(syncServiceProvider);
      final count = _everything ? null : await sync.pendingChangeCount(widget.peer.deviceId);
      final package = await sync.createPackage(widget.peer.deviceId, everything: _everything);
      if (!mounted) return;
      setState(() {
        _package = package;
        _changes = count;
      });
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String get _fileName => 'journal-${widget.peer.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.sjsync';

  void _note(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final package = _package;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send to ${widget.peer.name}', style: text.titleMedium),
            const SizedBox(height: 4),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (package == null && _error == null) const LinearProgressIndicator(),
            if (package != null) ...[
              Text(
                _everything
                    ? 'The whole journal (${(package.length / 1024).toStringAsFixed(0)} KB of text).'
                    : (_changes == 0 ? 'Nothing new since last time.' : '${_changes ?? 'All'} changes (${(package.length / 1024).toStringAsFixed(0)} KB of text).'),
                key: const ValueKey('send-summary'),
              ),
              SwitchListTile(
                key: const ValueKey('send-everything'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Send everything'),
                subtitle: const Text('Use this if the other device is missing things.'),
                value: _everything,
                onChanged: (v) {
                  _everything = v;
                  _build();
                },
              ),
              const SizedBox(height: Gap.sm),
              Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                FilledButton.icon(
                  key: const ValueKey('send-qr'),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Show QR codes'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Scan with the other device'),
                      content: SingleChildScrollView(child: QrFramePlayer(payload: package)),
                      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('send-share'),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  onPressed: () => ref.read(packageSharerProvider)(_fileName, package),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('send-file'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save file'),
                  onPressed: () async {
                    final saved = await ref.read(packageSaverProvider)(_fileName, package);
                    if (saved != null && mounted) _note('Saved $saved');
                  },
                ),
                OutlinedButton.icon(
                  key: const ValueKey('send-copy'),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy text'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: package));
                    if (mounted) _note('Copied. Send it to the other device any way you like.');
                  },
                ),
              ]),
              const SizedBox(height: Gap.sm),
              Text(
                'The text and file are encrypted. It is safe to send them through a message or email; only a paired device can open them.',
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
