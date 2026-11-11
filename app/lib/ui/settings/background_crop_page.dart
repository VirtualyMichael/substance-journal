import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../design.dart';

/// Lets the person move and zoom a picture under a fixed frame the shape of their screen, so the
/// part they care about is centred and it fills the screen properly. Pops the cropped picture as
/// PNG bytes, or null if they cancel.
class BackgroundCropPage extends StatefulWidget {
  const BackgroundCropPage({super.key, required this.image, required this.aspectRatio});

  final Uint8List image;

  /// Width over height of the screen the picture will fill.
  final double aspectRatio;

  @override
  State<BackgroundCropPage> createState() => _BackgroundCropPageState();
}

class _BackgroundCropPageState extends State<BackgroundCropPage> {
  final _controller = CropController();
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Position your picture')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Text(
              'Drag to move the picture and pinch or scroll to zoom. The frame is the shape of your screen, so what is inside it is what you will see.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Crop(
              key: const ValueKey('background-crop'),
              image: widget.image,
              controller: _controller,
              aspectRatio: widget.aspectRatio,
              interactive: true,
              fixCropRect: true,
              baseColor: Colors.black,
              maskColor: Colors.black.withValues(alpha: 0.6),
              progressIndicator: const CircularProgressIndicator(),
              onCropped: (result) {
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure():
                    setState(() {
                      _working = false;
                      _error = 'That picture could not be cropped. Try a different one.';
                    });
                }
              },
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(Gap.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: [
                  TextButton(key: const ValueKey('crop-cancel'), onPressed: _working ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const Spacer(),
                  FilledButton.icon(
                    key: const ValueKey('crop-use'),
                    icon: _working ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                    label: const Text('Use this picture'),
                    onPressed: _working
                        ? null
                        : () {
                            setState(() {
                              _working = true;
                              _error = null;
                            });
                            _controller.crop();
                          },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
