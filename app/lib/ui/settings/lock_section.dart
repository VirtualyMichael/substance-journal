import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_lock.dart';
import '../../providers.dart';
import '../design.dart';
import '../lock/lock_gate.dart';

/// Turns the app lock on and off, and sets how it behaves.
class LockSection extends ConsumerStatefulWidget {
  const LockSection({super.key});

  @override
  ConsumerState<LockSection> createState() => _LockSectionState();
}

class _LockSectionState extends ConsumerState<LockSection> {
  bool _deviceAvailable = false;

  @override
  void initState() {
    super.initState();
    ref.read(deviceAuthProvider).available().then((v) {
      if (mounted) setState(() => _deviceAvailable = v);
    });
  }

  Future<String?> _askPin(String title, {bool confirm = false}) => showDialog<String>(context: context, builder: (_) => _PinDialog(title: title, confirm: confirm));

  Future<void> _setPin(LockConfig current) async {
    final pin = await _askPin(current.enabled ? 'New PIN' : 'Choose a PIN', confirm: true);
    if (pin == null) return;
    final config = await lockWithPin(pin, previous: current);
    await ref.read(databaseProvider).saveLockConfig(config);
    // Setting the PIN is itself an unlock: do not lock the person out of the page they are on.
    ref.read(unlockedProvider.notifier).unlock();
  }

  Future<void> _turnOff(LockConfig current) async {
    final pin = await _askPin('Enter your PIN to turn the lock off');
    if (pin == null) return;
    if (!await pinMatches(current, pin)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That is not your PIN.')));
      return;
    }
    await ref.read(databaseProvider).clearLockConfig();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(lockConfigProvider).value ?? const LockConfig();
    final db = ref.read(databaseProvider);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('App lock', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Ask for a PIN (or your fingerprint, face or device unlock) when the app opens and after it has been away. '
          'This keeps other people out of the app. It does not encrypt the journal on this device; the device screen lock and encrypted backups do that.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Gap.sm),
        if (!config.enabled)
          FilledButton.icon(
            key: const ValueKey('lock-enable'),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Set a PIN'),
            onPressed: () => _setPin(config),
          )
        else ...[
          if (_deviceAvailable)
            SwitchListTile(
              key: const ValueKey('lock-use-device'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Fingerprint, face or device unlock'),
              subtitle: const Text('Also works if you forget the PIN.'),
              value: config.useDevice,
              onChanged: (v) => db.saveLockConfig(config.copyWith(useDevice: v)),
            ),
          Row(
            children: [
              const Text('Ask'),
              const SizedBox(width: Gap.sm),
              DropdownButton<int>(
                key: const ValueKey('lock-timeout'),
                value: config.timeoutSeconds,
                items: [for (final e in lockTimeouts.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => db.saveLockConfig(config.copyWith(timeoutSeconds: v)),
              ),
            ],
          ),
          Wrap(
            spacing: Gap.sm,
            children: [
              OutlinedButton(key: const ValueKey('lock-change'), onPressed: () => _setPin(config), child: const Text('Change PIN')),
              OutlinedButton(key: const ValueKey('lock-disable'), onPressed: () => _turnOff(config), child: const Text('Turn off')),
            ],
          ),
          if (!_deviceAvailable || !config.useDevice)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                'If you forget the PIN and device unlock is off, the only way back in is to clear the app\'s data, which deletes the journal unless you have a backup.',
                style: text.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.confirm});

  final String title;
  final bool confirm;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  void _done() {
    final pin = _pin.text.trim();
    if (!isValidPin(pin)) return setState(() => _error = 'Use 4 to 8 digits.');
    if (widget.confirm && pin != _again.text.trim()) return setState(() => _error = 'The two PINs do not match.');
    Navigator.pop(context, pin);
  }

  Widget _field(String key, String label, TextEditingController c, {bool autofocus = false}) => TextField(
        key: ValueKey(key),
        controller: c,
        autofocus: autofocus,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        decoration: InputDecoration(labelText: label),
        onSubmitted: (_) => _done(),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('pin-new', 'PIN (4 to 8 digits)', _pin, autofocus: true),
            if (widget.confirm) _field('pin-confirm', 'Type it again', _again),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const ValueKey('pin-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('pin-ok'), onPressed: _done, child: const Text('OK')),
        ],
      );
}
