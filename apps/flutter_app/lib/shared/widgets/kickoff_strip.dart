import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../models/match.dart';
import 'skeletons.dart';

/// The strip under the top bar naming the match: venue and kickoff in PHT, with
/// a way to change the match. Shell-coloured, so it reads as part of the board.
class KickoffStrip extends StatelessWidget {
  const KickoffStrip({super.key, required this.match, this.onChange});

  final MatchContext match;
  final VoidCallback? onChange;

  /// Content width from which venue and kickoff sit side by side.
  static const wideWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Match at ${match.venue.name}, kickoff ${formatPhtDateTime(match.kickoffAt)}',
      child: Container(
        width: double.infinity,
        color: p.shellRaised,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                // Phones stack venue over kickoff (venue names are long); wide
                // windows put venue left and kickoff right, as the contract shows.
                child: LayoutBuilder(
                  builder: (context, c) {
                    // Large text: venue and kickoff wrap rather than being cut
                    // (the kickoff time must always be readable in full).
                    final large = AppTheme.isLargeText(context);
                    final venue = Text(
                      match.venue.name,
                      style: text.bodyMedium?.copyWith(color: p.onShellMuted),
                      maxLines: large ? null : 1,
                      overflow: large ? null : TextOverflow.ellipsis,
                    );
                    final kickoff = Text(
                      'Kickoff ${formatPhtDateTime(match.kickoffAt)}',
                      style: text.titleMedium?.copyWith(color: p.onShell),
                      maxLines: large ? null : 1,
                      overflow: large ? null : TextOverflow.ellipsis,
                    );
                    return c.maxWidth >= wideWidth && !large
                        ? Row(
                            children: [
                              Expanded(child: venue),
                              const SizedBox(width: 16),
                              kickoff,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [venue, kickoff],
                          );
                  },
                ),
              ),
            ),
            if (onChange != null)
              TextButton(
                onPressed: onChange,
                style: TextButton.styleFrom(foregroundColor: p.onShell),
                child: const Text('Change'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The strip while the match loads: same height and padding as [KickoffStrip].
class KickoffStripSkeleton extends StatelessWidget {
  const KickoffStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    Widget line(TextStyle? style, double width) {
      final h = SkeletonLine.lineHeight(context, style);
      return SizedBox(
        height: h,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: width,
            height: h * 0.6,
            decoration: BoxDecoration(
              color: p.onShell.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(h),
            ),
          ),
        ),
      );
    }

    return SkeletonPulse(
      label: 'Loading match',
      child: Container(
        width: double.infinity,
        color: p.shellRaised,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: ConstrainedBox(
          // TextButton's minimum height keeps the real strip at least this tall.
          constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [line(text.bodyMedium, 200), line(text.titleMedium, 240)],
          ),
        ),
      ),
    );
  }
}
