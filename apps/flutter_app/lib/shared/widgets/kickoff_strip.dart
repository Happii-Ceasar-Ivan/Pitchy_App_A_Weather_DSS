import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/pht_time.dart';
import '../models/match.dart';
import '../models/weather.dart';
import 'press_scale.dart';
import 'skeletons.dart';
import 'source_rail.dart' show monoTimeRuns;

/// The strip under the top bar naming the match: venue and kickoff in PHT, with
/// a way to change the match. Shell-coloured, so it reads as part of the board.
class KickoffStrip extends StatelessWidget {
  const KickoffStrip({
    super.key,
    required this.match,
    this.onChange,
    this.sources,
    this.sourcesPending = false,
  });

  final MatchContext match;
  final VoidCallback? onChange;

  /// The backend's per-source states for this match, once loaded. Null: no
  /// summary (failed or saved copy). Only Current counts as current.
  final List<SourceStatus>? sources;

  /// Weather still loading: the summary's line is kept free, so nothing jumps.
  final bool sourcesPending;

  /// "2 of 3 sources current", or null when there are no loaded sources.
  static String? summary(List<SourceStatus>? sources) {
    if (sources == null || sources.isEmpty) return null;
    final n = sources.where((s) => s.state == WeatherDataState.current).length;
    return '$n of ${sources.length} sources current';
  }

  /// Content width from which venue and kickoff sit side by side.
  static const wideWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label:
          'Match at ${match.venue.name}, kickoff ${formatPhtDateTime(match.kickoffAt)}'
          '${summary(sources) == null ? '' : '. ${summary(sources)}'}',
      child: Container(
        width: double.infinity,
        color: p.shellRaised,
        padding: const EdgeInsets.fromLTRB(
          PitchySpace.lg,
          PitchySpace.sm,
          PitchySpace.sm,
          PitchySpace.sm,
        ),
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
                    // Two lines at normal sizes: the kickoff time is never cut
                    // on a narrow phone ("Wed 25 Nov, 11:00 PM PHT").
                    final venue = Text(
                      match.venue.name,
                      style: text.bodyMedium?.copyWith(color: p.onShellMuted),
                      maxLines: large ? null : 2,
                      overflow: large ? null : TextOverflow.ellipsis,
                    );
                    final kickoff = Text.rich(
                      monoTimeRuns(
                        'Kickoff ${formatPhtDateTime(match.kickoffAt)}',
                        text.titleMedium?.copyWith(color: p.onShell),
                      ),
                      maxLines: large ? null : 2,
                      overflow: large ? null : TextOverflow.ellipsis,
                    );
                    final text0 = summary(sources);
                    final count = text0 != null
                        ? Text(
                            text0,
                            key: const ValueKey('sources-current'),
                            style: text.bodySmall?.copyWith(color: p.onShellMuted),
                          )
                        : sourcesPending
                        ? SizedBox(height: SkeletonLine.lineHeight(context, text.bodySmall))
                        : null;
                    final head = c.maxWidth >= wideWidth && !large
                        ? Row(
                            children: [
                              Expanded(child: venue),
                              const SizedBox(width: PitchySpace.lg),
                              kickoff,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [venue, kickoff],
                          );
                    return count == null
                        ? head
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [head, count],
                          );
                  },
                ),
              ),
            ),
            if (onChange != null)
              PitchyPressScale(
                child: TextButton(
                  onPressed: onChange,
                  style: TextButton.styleFrom(foregroundColor: p.onShell),
                  child: const Text('Change'),
                ),
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
        padding: const EdgeInsets.fromLTRB(
          PitchySpace.lg,
          PitchySpace.sm,
          PitchySpace.sm,
          PitchySpace.sm,
        ),
        child: ConstrainedBox(
          // TextButton's minimum height keeps the real strip at least this tall.
          constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(text.bodyMedium, 200),
              line(text.titleMedium, 240),
              line(text.bodySmall, 150),
            ],
          ),
        ),
      ),
    );
  }
}
