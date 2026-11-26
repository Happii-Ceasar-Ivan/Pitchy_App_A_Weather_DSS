import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a fixed app URL in the system browser; says so if it can't.
Future<void> openExternalLink(BuildContext context, Uri url) async {
  final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Couldn’t open the link. It is $url')),
    );
  }
}

/// A tappable link that opens in the system browser. Only for fixed URLs the
/// app ships with (credits); never for text that came from a source.
class LinkText extends StatelessWidget {
  const LinkText(this.url, {super.key, this.label});

  final String url;
  final String? label;

  Future<void> _open(BuildContext context) => openExternalLink(context, Uri.parse(url));

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      link: true,
      label: label ?? url,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label ?? url,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
