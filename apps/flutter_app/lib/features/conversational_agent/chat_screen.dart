import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';

/// PitChyAT (P-14) shell. The conversation arrives in Sprint F4, after the
/// backend's conversation (B5) and session (B6) endpoints exist.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'PitChyAT'),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: palette.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: palette.inkMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'PitChyAT explains conditions and approved guidance. Its answers are '
                    'explanations, not official decisions.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: palette.hairline),
          const Expanded(
            child: EmptyState(
              icon: Icons.forum_outlined,
              title: 'PitChyAT isn’t available yet',
              detail:
                  'You’ll be able to ask about the weather and safety guidance for your '
                  'match, as a Coach, Match Official, Referee, Medical Staff or Spectator.',
            ),
          ),
        ],
      ),
    );
  }
}
