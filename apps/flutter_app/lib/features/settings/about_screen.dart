import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/spacing.dart';
import '../../shared/widgets/pitchy_logo.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/press_scale.dart';

/// About Pitchy: what the app is, its version, and a way to the credits.
/// Wording comes from the project's own description (PRODUCT.md, SRS).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final info = AppScope.of(context).info;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'About Pitchy'),
      body: ListView(
        padding: const EdgeInsets.all(PitchySpace.lg),
        children: [
          Row(
            children: [
              const PitchyLogo(size: 56),
              const SizedBox(width: PitchySpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pitchy', style: text.headlineSmall),
                    Text(
                      'Version ${info.label}',
                      style: text.bodyMedium?.copyWith(color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: PitchySpace.xl),
          Text(
            'Pitchy is a multi-source weather decision-support app for football safety. For a '
            'chosen venue and kickoff time it shows weather from several sources, how current each '
            'one is, and the safety assessment and approved guidance from the Pitchy server.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: PitchySpace.md),
          Text(
            'It supports authorized decision-makers; it does not replace them. Ask Pitchy explains '
            'conditions and guidance, but its answers are not official decisions.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: PitchySpace.md),
          Text('All times are shown in Philippine Time (PHT).', style: text.bodyMedium),
          const SizedBox(height: PitchySpace.xl),
          PitchyPressScale(
            child: OutlinedButton.icon(
              onPressed: () => context.push(Routes.credits),
              icon: const Icon(Icons.attribution_outlined),
              label: const Text('Credits'),
            ),
          ),
        ],
      ),
    );
  }
}
