import 'package:material_ui/material_ui.dart';

import '../../core/theme/spacing.dart';
import '../../shared/widgets/link_text.dart';
import '../../shared/widgets/pitchy_top_bar.dart';

/// All credits live here (P-13), including the Open-Meteo attribution and link.
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
    (
      'Lightning data: Powered by Vaisala Xweather',
      'Real-time lightning detection near the venue, shown on the Safety tab.',
      'https://www.xweather.com/',
    ),
    (
      'Switzer typeface',
      'By Indian Type Foundry, ITF Free Font License.',
      'https://www.fontshare.com/fonts/switzer',
    ),
    ('IBM Plex Mono', 'By IBM, SIL Open Font License 1.1.', 'https://github.com/IBM/plex'),
    ('Material icons', 'Google, Apache License 2.0.', 'https://fonts.google.com/icons'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PitchyTopBar(title: 'Credits'),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: PitchySpace.sm),
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
                const SizedBox(height: PitchySpace.xs),
                Text(detail),
                LinkText(url),
              ],
            ),
          );
        },
      ),
    );
  }
}
