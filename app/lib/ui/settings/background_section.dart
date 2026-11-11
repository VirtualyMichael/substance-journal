import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/background_config.dart';
import '../../providers.dart';
import '../background/app_background.dart';
import '../design.dart';
import 'background_crop_page.dart';

/// Asks for a picture or GIF. Replaced in tests so no real dialog opens.
final backgroundFilePickerProvider = Provider<Future<String?> Function()>((ref) => () async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        dialogTitle: 'Choose a background picture or GIF',
      );
      return file?.path;
    });

/// Settings block for the picture behind the app.
class BackgroundSection extends ConsumerWidget {
  const BackgroundSection({super.key});

  Future<void> _save(WidgetRef ref, BackgroundConfig c) => ref.read(databaseProvider).saveBackground(c);

  Future<void> _choosePhoto(BuildContext context, WidgetRef ref, BackgroundConfig current) async {
    final picked = await ref.read(backgroundFilePickerProvider)();
    if (picked == null || !context.mounted) return;
    final isGif = p.extension(picked).toLowerCase() == '.gif';
    Uint8List? cropped;
    if (!isGif) {
      // Let the person move and zoom the picture under a frame the shape of this screen.
      final size = MediaQuery.sizeOf(context);
      cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => BackgroundCropPage(image: File(picked).readAsBytesSync(), aspectRatio: size.width / size.height)),
      );
      if (cropped == null) return;
    }
    // Keep our own copy so the background survives the original being moved or deleted.
    final folder = Directory(p.join((await getApplicationSupportDirectory()).path, 'background'));
    await folder.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final File target;
    if (cropped == null) {
      // A GIF is kept as it is: cropping would flatten the animation.
      target = File(p.join(folder.path, 'background-$stamp.gif'));
      await File(picked).copy(target.path);
    } else {
      target = File(p.join(folder.path, 'background-$stamp.png'));
      await target.writeAsBytes(cropped);
    }
    final old = current.imagePath;
    await _save(ref, current.copyWith(mode: BackgroundMode.image, imagePath: target.path));
    if (old != null && old != target.path && p.dirname(old) == folder.path) {
      try {
        File(old).deleteSync();
      } on Object {
        // Leave it.
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(backgroundProvider).value ?? const BackgroundConfig();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Background', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('A slow flow of colour (or your own picture or GIF) behind every screen. Animation uses a little battery; "Still" does not.', style: text.bodySmall),
        const SizedBox(height: Gap.sm),
        SegmentedButton<BackgroundMode>(
          key: const ValueKey('background-mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: BackgroundMode.off, label: Text('Off')),
            ButtonSegment(value: BackgroundMode.flow, label: Text('Flow')),
            ButtonSegment(value: BackgroundMode.still, label: Text('Still')),
            ButtonSegment(value: BackgroundMode.image, label: Text('Photo')),
          ],
          selected: {c.mode},
          onSelectionChanged: (s) async {
            final mode = s.first;
            if (mode == BackgroundMode.image && c.imagePath == null) {
              await _choosePhoto(context, ref, c);
            } else {
              await _save(ref, c.copyWith(mode: mode));
            }
          },
        ),
        if (c.mode == BackgroundMode.flow || c.mode == BackgroundMode.still) ...[
          const SizedBox(height: Gap.md),
          Text('Colours', style: text.titleSmall),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final pal in flowPalettes)
                ChoiceChip(
                  key: ValueKey('palette-${pal.id}'),
                  avatar: CircleAvatar(backgroundColor: pal.bright, radius: 8),
                  label: Text(pal.name),
                  selected: c.palette == pal.id,
                  onSelected: (_) => _save(ref, c.copyWith(palette: pal.id)),
                ),
            ],
          ),
        ],
        if (c.mode == BackgroundMode.flow || c.mode == BackgroundMode.still) ...[
          const SizedBox(height: Gap.md),
          Text('Quality', style: text.titleSmall),
          const SizedBox(height: 2),
          Text('Higher is smoother and finer but uses more battery. Pick Low if it ever stutters.', style: text.bodySmall),
          const SizedBox(height: Gap.sm),
          SegmentedButton<BackgroundQuality>(
            key: const ValueKey('background-quality'),
            showSelectedIcon: false,
            segments: [for (final q in BackgroundQuality.values) ButtonSegment(value: q, label: Text(q.label))],
            selected: {c.quality},
            onSelectionChanged: (v) => _save(ref, c.copyWith(quality: v.first)),
          ),
        ],
        if (c.mode == BackgroundMode.image) ...[
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            key: const ValueKey('background-photo'),
            icon: const Icon(Icons.image_outlined),
            label: Text(c.imagePath == null ? 'Choose a picture or GIF...' : 'Change picture or GIF...'),
            onPressed: () => _choosePhoto(context, ref, c),
          ),
        ],
        if (c.active) ...[
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              const Text('Readability'),
              Expanded(
                child: _DimSlider(value: c.dim, onSaved: (v) => _save(ref, c.copyWith(dim: v))),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Follows the finger smoothly and saves once, when it is lifted.
class _DimSlider extends StatefulWidget {
  const _DimSlider({required this.value, required this.onSaved});

  final double value;
  final ValueChanged<double> onSaved;

  @override
  State<_DimSlider> createState() => _DimSliderState();
}

class _DimSliderState extends State<_DimSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    return Slider(
      key: const ValueKey('background-dim'),
      value: v,
      max: 0.8,
      divisions: 16,
      label: '${(v * 100).round()}%',
      onChanged: (x) => setState(() => _dragging = x),
      onChangeEnd: (x) {
        widget.onSaved(x);
        setState(() => _dragging = null);
      },
    );
  }
}
