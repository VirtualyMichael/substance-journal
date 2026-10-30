import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'toast.dart';

/// A source reference. Web links open in the browser (long press copies the address); anything
/// that is not a link is shown as plain selectable text.
class LinkTile extends ConsumerWidget {
  const LinkTile(this.source, {super.key, this.label, this.description});

  final String source;

  /// Text to show instead of the address.
  final String? label;

  /// One line about what the link leads to.
  final String? description;

  static Uri? asUri(String s) {
    final uri = Uri.tryParse(s.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? uri : null;
  }

  /// "pubmed.ncbi.nlm.nih.gov/17064864" style: readable, without scheme or "www.".
  static String shortName(Uri uri) {
    final host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
    final path = Uri.decodeFull(uri.path).replaceAll(RegExp(r'/+$'), '');
    final text = '$host$path';
    return text.length > 64 ? '${text.substring(0, 61)}...' : text;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme.bodyMedium;
    final uri = asUri(source);
    if (uri == null) return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(source, style: text));
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('link-$source'),
      onTap: () async {
        final opened = await ref.read(urlOpenerProvider)(uri);
        if (!opened && context.mounted) {
          await Clipboard.setData(ClipboardData(text: uri.toString()));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showToast(const SnackBar(content: Text('Could not open a browser, so the link was copied.')));
          }
        }
      },
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        if (context.mounted) ScaffoldMessenger.of(context).showToast(const SnackBar(content: Text('Link copied')));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.open_in_new, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label ?? shortName(uri),
                    style: text?.copyWith(color: scheme.primary, decoration: TextDecoration.underline, decorationColor: scheme.primary),
                  ),
                  if (description != null) Text(description!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
