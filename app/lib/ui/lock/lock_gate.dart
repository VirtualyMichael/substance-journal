import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/app_lock.dart';
import '../../providers.dart';
import '../design.dart';

/// The device's own unlock: fingerprint, face, or the screen lock / Windows Hello. Replaced in tests.
abstract class DeviceAuth {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class LocalDeviceAuth implements DeviceAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } on Object {
      return false;
    }
  }
}

final deviceAuthProvider = Provider<DeviceAuth>((ref) => LocalDeviceAuth());

final lockConfigProvider = StreamProvider<LockConfig>((ref) => ref.watch(databaseProvider).watchLockConfig());

/// Whether the app has been opened with the PIN or device unlock since it started (or last locked).
class Unlocked extends Notifier<bool> {
  int _failures = 0;
  DateTime? _waitUntil;

  /// True while the device's own prompt is up: it pauses the app, which must not count as leaving it.
  bool authenticating = false;

  @override
  bool build() => false;

  void unlock() {
    _failures = 0;
    _waitUntil = null;
    state = true;
  }

  void lock() => state = false;

  /// Seconds left before another PIN try is allowed (after five wrong ones, then doubling).
  int secondsToWait(DateTime now) {
    final until = _waitUntil;
    if (until == null || !until.isAfter(now)) return 0;
    return until.difference(now).inSeconds + 1;
  }

  void failed(DateTime now) {
    _failures++;
    if (_failures >= 5) {
      final seconds = (30 * (1 << (_failures - 5).clamp(0, 5))).clamp(30, 900);
      _waitUntil = now.add(Duration(seconds: seconds));
    }
  }
}

final unlockedProvider = NotifierProvider<Unlocked, bool>(Unlocked.new);

/// Keeps the journal behind the lock screen when a PIN is set: at start, and after the app has been
/// away longer than the chosen time. While the app is in the background the screen is covered so
/// the app switcher never shows the journal.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = ref.read(clockProvider)();
    final unlocked = ref.read(unlockedProvider.notifier);
    final config = ref.read(lockConfigProvider).value;
    if (config != null && config.enabled && !unlocked.authenticating) {
      if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
        _leftAt ??= now;
      } else if (state == AppLifecycleState.resumed && _leftAt != null) {
        if (now.difference(_leftAt!).inSeconds >= config.timeoutSeconds) unlocked.lock();
        _leftAt = null;
      }
    }
    setState(() => _lifecycle = state);
  }

  bool get _coverWhenInactive => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(lockConfigProvider);
    final unlocked = ref.watch(unlockedProvider);
    final enabled = config.value?.enabled ?? false;
    if (config.isLoading) return const ColoredBox(color: Colors.black);
    if (!enabled) return widget.child;

    final away = _lifecycle == AppLifecycleState.hidden ||
        _lifecycle == AppLifecycleState.paused ||
        (_lifecycle == AppLifecycleState.inactive && _coverWhenInactive);
    final cover = !unlocked || away;
    return Stack(
      children: [
        // Hidden, not removed, so the journal is exactly where it was after unlocking.
        Offstage(offstage: cover, child: TickerMode(enabled: !cover, child: widget.child)),
        if (!unlocked)
          Positioned.fill(
            child: Overlay(initialEntries: [OverlayEntry(builder: (_) => LockScreen(config: config.value!))]),
          ),
        if (unlocked && away) const Positioned.fill(child: _PrivacyCover()),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: Center(child: Icon(Icons.lock_outline, size: 48, color: Theme.of(context).colorScheme.outline)));
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.config});

  final LockConfig config;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _checking = false;
  bool _deviceAvailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.config.useDevice) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _deviceAvailable = await ref.read(deviceAuthProvider).available();
        if (!mounted) return;
        setState(() {});
        if (_deviceAvailable) await _device();
      });
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _device() async {
    final unlocked = ref.read(unlockedProvider.notifier);
    unlocked.authenticating = true;
    final ok = await ref.read(deviceAuthProvider).authenticate('Unlock Substance Journal');
    unlocked.authenticating = false;
    if (ok && mounted) unlocked.unlock();
  }

  Future<void> _submit() async {
    final notifier = ref.read(unlockedProvider.notifier);
    final now = ref.read(clockProvider)();
    final wait = notifier.secondsToWait(now);
    if (wait > 0) {
      setState(() => _error = 'Too many tries. Wait $wait seconds.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await pinMatches(widget.config, _pin.text.trim());
    if (!mounted) return;
    if (ok) {
      notifier.unlock();
      return;
    }
    notifier.failed(now);
    final after = notifier.secondsToWait(now);
    setState(() {
      _checking = false;
      _pin.clear();
      _error = after > 0 ? 'Wrong PIN. Wait $after seconds before trying again.' : 'Wrong PIN.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: scheme.primary),
                  const SizedBox(height: Gap.md),
                  Text('Substance Journal is locked', style: text.titleMedium),
                  const SizedBox(height: Gap.md),
                  TextField(
                    key: const ValueKey('lock-pin'),
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(labelText: 'PIN', errorText: _error),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: Gap.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(key: const ValueKey('lock-unlock'), onPressed: _checking ? null : _submit, child: const Text('Unlock')),
                  ),
                  if (widget.config.useDevice && _deviceAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: TextButton.icon(
                        key: const ValueKey('lock-device'),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use fingerprint, face or device unlock'),
                        onPressed: _device,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
