import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';

/// Match setup shell (F0). Venue picker and PHT kickoff entry arrive in Sprint F1.
class MatchSetupScreen extends StatelessWidget {
  const MatchSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    appBar: PitchyTopBar(title: 'Set up a match'),
    body: EmptyState(
      icon: Icons.construction,
      title: 'Match setup is coming next',
      detail:
          'You’ll pick Rizal Memorial Stadium or New Clark City and a kickoff time in '
          'Philippine Time (PHT).',
    ),
  );
}
