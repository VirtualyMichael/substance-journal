import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_lock.dart';
import '../data/assistant_link.dart';
import '../providers.dart';
import 'design.dart';
import 'lock/lock_gate.dart';
import 'settings/lock_section.dart';
import 'toast.dart';

/// The voice assistant link (see data/assistant_link.dart): computers only.
final assistantLinkSupportedProvider = Provider<bool>((ref) => Platform.isWindows || Platform.isLinux);

/// `voice-assistant` in the app's data folder, beside the journal.
final assistantLinkFolderProvider = Provider<Future<Directory> Function()>(
  (ref) => () async => Directory(p.join((await getApplicationSupportDirectory()).path, 'voice-assistant')),
);

/// Makes a link for this app's database. Replaced in widget tests.
final assistantLinkFactoryProvider = Provider<Future<AssistantLinkHandle> Function()>((ref) => () async {
      final folder = await ref.read(assistantLinkFolderProvider)();
      return AssistantLink(
        db: ref.read(databaseProvider),
        folder: folder,
        reference: () => ref.read(catalogProvider),
        now: ref.read(clockProvider),
      );
    });

const assistantAutoStartKey = 'assistantLinkAutoStart';

/// "Turn on again when the app starts" (this device only; off unless ticked).
final assistantAutoStartProvider = StreamProvider<bool>(
  (ref) => ref.watch(databaseProvider).watchSetting(assistantAutoStartKey).map((v) => v == 'true'),
);

class AssistantLinkState {
  const AssistantLinkState({this.on = false, this.port, this.error});
  final bool on;
  final int? port;
  final String? error;
}

/// Whether the link is on. It is only ever turned on by the person (or by their "turn on again when
/// the app starts"), and goes off with the app.
class AssistantLinkController extends Notifier<AssistantLinkState> {
  AssistantLinkHandle? _link;
  StreamSubscription<LinkAddition>? _sub;
  final _events = StreamController<LinkAddition>.broadcast();

  /// Entries added through the link while it is on.
  Stream<LinkAddition> get additions => _events.stream;

  @override
  AssistantLinkState build() {
    ref.onDispose(() {
      _sub?.cancel();
      final link = _link;
      _link = null;
      if (link != null) unawaited(link.stop().catchError((Object _) {}));
      _events.close();
    });
    return const AssistantLinkState();
  }

  Future<bool> turnOn() async {
    if (_link != null) return true;
    try {
      final link = await ref.read(assistantLinkFactoryProvider)();
      final port = await link.start();
      _link = link;
      _sub = link.additions.listen(_events.add);
      state = AssistantLinkState(on: true, port: port);
      return true;
    } on Object catch (e) {
      state = AssistantLinkState(error: 'The link could not start: $e');
      return false;
    }
  }

  Future<void> turnOff() async {
    final link = _link;
    _link = null;
    await _sub?.cancel();
    _sub = null;
    state = const AssistantLinkState();
    await link?.stop();
  }

  /// The Undo on "Added by your voice assistant".
  Future<bool> undo(LinkAddition a) async => await _link?.undoFromApp(a) ?? false;
}

final assistantLinkProvider = NotifierProvider<AssistantLinkController, AssistantLinkState>(AssistantLinkController.new);

/// Asks for the app lock (device unlock if the person allowed it, else the PIN) when one is set.
/// True when there is no lock or it was passed. Wrong PINs count towards the lock's own wait.
Future<bool> passAppLock(BuildContext context, WidgetRef ref, {required String reason, required String pinTitle}) async {
  final config = ref.read(lockConfigProvider).value ?? const LockConfig();
  if (!config.enabled) return true;
  final notifier = ref.read(unlockedProvider.notifier);
  if (config.useDevice) {
    final auth = ref.read(deviceAuthProvider);
    if (await auth.available()) {
      notifier.authenticating = true;
      final ok = await auth.authenticate(reason);
      notifier.authenticating = false;
      if (ok) return true;
    }
  }
  if (!context.mounted) return false;
  await notifier.restore();
  final now = ref.read(clockProvider)();
  final wait = notifier.secondsToWait(now);
  if (wait > 0) {
    if (context.mounted) ScaffoldMessenger.of(context).showToast(SnackBar(content: Text('Too many tries. Wait $wait seconds.')));
    return false;
  }
  if (!context.mounted) return false;
  final pin = await showDialog<String>(context: context, builder: (_) => PinDialog(title: pinTitle));
  if (pin == null) return false;
  if (await pinMatches(config, pin)) {
    notifier.unlock();
    return true;
  }
  notifier.failed(now);
  if (context.mounted) ScaffoldMessenger.of(context).showToast(const SnackBar(content: Text('That is not your PIN.')));
  return false;
}

/// Settings > Summary for an AI > Voice assistant.
class VoiceAssistantSection extends ConsumerWidget {
  const VoiceAssistantSection({super.key});

  static const switchLabel = 'Let my voice assistant add entries while this app is open';
  static const explanation =
      'It can add doses, drinks and notes, and undo its own recent ones. It cannot read your whole journal through this link, '
      'edit or delete your entries, or see anything when the app is closed.';

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    if (!await passAppLock(context, ref, reason: 'Link your voice assistant', pinTitle: 'Enter your PIN to link your voice assistant')) return;
    final ok = await ref.read(assistantLinkProvider.notifier).turnOn();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showToast(SnackBar(content: Text(ref.read(assistantLinkProvider).error ?? 'The link could not start.')), important: true);
    }
  }

  Future<void> _setAutoStart(BuildContext context, WidgetRef ref, bool value) async {
    if (value && !await passAppLock(context, ref, reason: 'Link your voice assistant at start', pinTitle: 'Enter your PIN to turn this on')) return;
    await ref.read(databaseProvider).setSetting(assistantAutoStartKey, value ? 'true' : 'false');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(assistantLinkSupportedProvider)) return const SizedBox.shrink();
    final link = ref.watch(assistantLinkProvider);
    final autoStart = ref.watch(assistantAutoStartProvider).value ?? false;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Voice assistant', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(explanation, style: text.bodySmall),
        SwitchListTile(
          key: const ValueKey('assistant-link'),
          contentPadding: EdgeInsets.zero,
          title: const Text(switchLabel),
          value: link.on,
          onChanged: (v) => v ? _turnOn(context, ref) : ref.read(assistantLinkProvider.notifier).turnOff(),
        ),
        CheckboxListTile(
          key: const ValueKey('assistant-autostart'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Turn on again when the app starts'),
          value: autoStart,
          onChanged: (v) => _setAutoStart(context, ref, v ?? false),
        ),
        Text(
          link.on
              ? 'Linked on this computer only. The link file (with its key for the assistant, not your journal\'s key) can be read by programs running as your user while the link is on, so turn it off when you do not need it.'
              : 'The assistant gets a key for this link only, never the journal\'s key, and a new one each time you turn it on.',
          key: const ValueKey('assistant-link-note'),
          style: text.bodySmall,
        ),
        if (link.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(link.error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: Gap.xs),
      ],
    );
  }
}

/// Wraps the main screen: a "Voice assistant linked" strip while the link is on, a message with Undo
/// for every entry it adds, turning on at start when the person asked for that (after the app lock),
/// and turning off when the app closes.
class VoiceAssistantHost extends ConsumerStatefulWidget {
  const VoiceAssistantHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<VoiceAssistantHost> createState() => _VoiceAssistantHostState();
}

class _VoiceAssistantHostState extends ConsumerState<VoiceAssistantHost> {
  StreamSubscription<LinkAddition>? _sub;
  AppLifecycleListener? _exit;
  bool _autoStartTried = false;

  @override
  void initState() {
    super.initState();
    if (!ref.read(assistantLinkSupportedProvider)) return;
    _sub = ref.read(assistantLinkProvider.notifier).additions.listen(_show);
    _exit = AppLifecycleListener(onExitRequested: () async {
      try {
        await ref.read(assistantLinkProvider.notifier).turnOff().timeout(const Duration(seconds: 2));
      } on Object {
        // Closing must never be held up; a left-over file names a port nobody answers.
      }
      return AppExitResponse.exit;
    });
    if (!Platform.environment.containsKey('FLUTTER_TEST')) unawaited(_removeStaleFile());
  }

  Future<void> _removeStaleFile() async {
    try {
      if (ref.read(assistantLinkProvider).on) return;
      await AssistantLink.removeStaleLinkFile(await ref.read(assistantLinkFolderProvider)());
    } on Object {
      // No data folder yet: nothing to remove.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _exit?.dispose();
    super.dispose();
  }

  void _show(LinkAddition a) {
    if (!mounted) return;
    final controller = ref.read(assistantLinkProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showToast(
      SnackBar(
        content: Text('Added by your voice assistant: ${a.summary}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final done = await controller.undo(a);
            messenger.showToast(SnackBar(content: Text(done ? 'Removed what your voice assistant added.' : 'Already removed or changed.')), important: true);
          },
        ),
      ),
      important: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(assistantLinkSupportedProvider)) return widget.child;
    final link = ref.watch(assistantLinkProvider);
    final autoStart = ref.watch(assistantAutoStartProvider).value ?? false;
    final lock = ref.watch(lockConfigProvider).value;
    final unlocked = ref.watch(unlockedProvider);
    if (autoStart && !_autoStartTried && !link.on && lock != null && (!lock.enabled || unlocked)) {
      _autoStartTried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(assistantLinkProvider.notifier).turnOn());
    }
    if (!link.on) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.record_voice_over_outlined, size: 18, color: scheme.onTertiaryContainer),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text('Voice assistant linked', key: const ValueKey('assistant-linked'), style: TextStyle(color: scheme.onTertiaryContainer)),
                ),
                TextButton(
                  key: const ValueKey('assistant-banner-off'),
                  onPressed: () => ref.read(assistantLinkProvider.notifier).turnOff(),
                  child: const Text('Turn off'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
