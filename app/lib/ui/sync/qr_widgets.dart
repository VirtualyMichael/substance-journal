import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sj_core/sj_core.dart';

import '../design.dart';

/// One static QR code (a pairing code).
class QrCard extends StatelessWidget {
  const QrCard({super.key, required this.data, this.size = 260});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Always dark on white, whatever the theme, so camera apps can read it.
    return Container(
      padding: const EdgeInsets.all(Gap.sm),
      color: Colors.white,
      // A painter rather than QrImageView: that widget cannot be measured inside a dialog.
      child: CustomPaint(
        size: Size.square(size),
        painter: QrPainter(
          data: data,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
        ),
      ),
    );
  }
}

/// A sealed package as a looping series of QR codes. Point the other device's camera at it; the
/// frames can be read in any order, so it does not matter when scanning starts.
class QrFramePlayer extends StatefulWidget {
  const QrFramePlayer({super.key, required this.payload, this.frameSize = 500, this.interval = const Duration(milliseconds: 450)});

  final String payload;
  final int frameSize;
  final Duration interval;

  @override
  State<QrFramePlayer> createState() => _QrFramePlayerState();
}

class _QrFramePlayerState extends State<QrFramePlayer> {
  late final List<String> _frames = splitIntoFrames(widget.payload, frameSize: widget.frameSize);
  int _index = 0;
  Timer? _timer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!_paused && mounted && _frames.length > 1) setState(() => _index = (_index + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        QrCard(key: const ValueKey('qr-frame'), data: _frames[_index], size: 300),
        const SizedBox(height: Gap.sm),
        Text('Code ${_index + 1} of ${_frames.length}', key: const ValueKey('qr-frame-label'), style: text.bodySmall),
        const SizedBox(height: 4),
        Text(
          _frames.length == 1
              ? 'Scan this on the other device.'
              : 'Keep this open and scan it on the other device. It repeats until every code has been read.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        TextButton.icon(
          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          label: Text(_paused ? 'Resume' : 'Pause'),
          onPressed: () => setState(() => _paused = !_paused),
        ),
      ],
    );
  }
}

/// Opens the camera and collects QR codes until [accept] says it has what it needs.
///
/// [accept] receives each decoded text and returns a progress message, or null when it has
/// finished (the page then closes with the final text from [result]).
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, required this.title, required this.hint, required this.onText});

  final String title;
  final String hint;

  /// Called with each decoded text. Return a status line to keep scanning, or a [ScanDone] to finish.
  final Object Function(String text) onText;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

/// Returned from the scan callback to close the page with [value].
class ScanDone {
  const ScanDone(this.value);
  final String value;
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  String? _status;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      final result = widget.onText(raw);
      if (result is ScanDone) {
        _done = true;
        Navigator.of(context).pop(result.value);
        return;
      }
      if (result is String && result != _status) setState(() => _status = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _detect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Text('The camera is not available: ${error.errorDetails?.message ?? error.errorCode.name}. '
                    'Allow camera access for this app, or use paste or a file instead.'),
              ),
            ),
          ),
          Positioned(
            left: Gap.md,
            right: Gap.md,
            bottom: Gap.xl,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Text(_status ?? widget.hint, key: const ValueKey('scan-status')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
