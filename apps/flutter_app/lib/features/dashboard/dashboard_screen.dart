import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/app_router.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';

/// Dashboard shell (F0). The match overview, source rail and weather cards are
/// built here in Sprint F1, from the shared components.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PitchyTopBar(title: 'Dashboard'),
    body: EmptyState(
      icon: Icons.sports_soccer,
      title: 'No match set up',
      detail:
          'Choose a venue and kickoff time to see the weather sources and conditions for '
          'your match.',
      action: FilledButton.icon(
        onPressed: () => context.push(Routes.matchSetup),
        icon: const Icon(Icons.add),
        label: const Text('Set up a match'),
      ),
    ),
  );
}
