import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/pitchy_top_bar.dart';

/// All credits live here (P-13), including the Open-Meteo attribution and link.
/// Links become tappable when the link-opening package is added (F1).
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  static const credits = <(String, String, String)>[
    ('Weather data by Open-Meteo.com', 'Licensed under CC BY 4.0.', 'https://open-meteo.com/'),
    (
      'PAGASA',
      'Forecasts and official alerts from the Philippine Atmospheric, Geophysical and '
          'Astronomical Services Administration (panahon.gov.ph).',
      'https://www.panahon.gov.ph/',
    ),
    ('Roboto typeface', 'Google, Apache License 2.0.', 'https://fonts.google.com/specimen/Roboto'),
    ('Material icons', 'Google, Apache License 2.0.', 'https://fonts.google.com/icons'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'Credits'),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: credits.length + 1,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, i) {
          if (i == credits.length) {
            return ListTile(
              title: const Text('Open-source licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context, applicationName: 'Pitchy'),
            );
          }
          final (title, detail, url) = credits[i];
          return ListTile(
            title: Text(title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(detail),
                const SizedBox(height: 4),
                SelectableText(
                  url,
                  style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
