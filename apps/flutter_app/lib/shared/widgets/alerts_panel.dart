import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../models/alerts.dart';
import '../models/weather.dart';
import 'alert_level.dart';
import 'data_state_badge.dart';
import 'skeletons.dart';

/// Official alerts for the match's venue (FR-SAF-007), above the board.
///
/// Alert text comes from PAGASA and is untrusted: it is shown only through
/// plain [Text] widgets, never as HTML, Markdown or links. Colours stay
/// neutral: the app doesn't grade an alert's severity; the agency's own words
/// (event, subtype, headline) say what it is.
///
/// Collapsed, the panel always has one shape (a header row and one two-line
/// row), so it lands exactly where its skeleton was. Tapping it shows every
/// alert in full.
class AlertsPanel extends StatefulWidget {
  const AlertsPanel({super.key, required this.alerts, this.onRetry});

  final Loadable<VenueAlerts> alerts;
  final VoidCallback? onRetry;

  @override
  State<AlertsPanel> createState() => _AlertsPanelState();
}

class _AlertsPanelState extends State<AlertsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => switch (widget.alerts) {
    Loading() => const AlertsPanelSkeleton(),
    // The DEC-13 saved copy (server unreachable): never worded as live.
    Failed(saved: SavedCopy(:final value, :final savedAt)) => SavedCopyScope(
      savedAt: savedAt,
      child: Builder(builder: (context) => _loaded(context, value, savedAt: savedAt)),
    ),
    Failed(:final failure) => _Frame(
      header: const _Header(title: 'Alerts'),
      row: _FailedRow(failure: failure, onRetry: widget.onRetry),
    ),
    Loaded(:final value) => _loaded(context, value),
  };

  Widget _loaded(BuildContext context, VenueAlerts v, {DateTime? savedAt}) {
    final checked = v.status.lastCheckedAt;
    final header = _Header(
      title: savedAt != null
          ? 'Alerts · saved copy from ${formatPhtTime(savedAt)}'
          : checked == null
          ? 'Alerts'
          : 'Alerts · checked ${formatPhtTime(checked)}',
      state: v.status.state,
    );
    if (v.alerts.isEmpty) {
      return _Frame(
        header: header,
        row: _EmptyRow(state: v.status.state, checkedAt: checked),
      );
    }
    // Most severe first (by PAGASA's own level words, P-18).
    final first = bySeverity(v.alerts).first;
    final more = v.alerts.length - 1;
    return _Frame(
      header: header,
      row: _AlertRow(alert: first, more: more, expanded: _expanded),
      onTap: () => setState(() => _expanded = !_expanded),
      details: _expanded ? _AlertDetails(alerts: v) : null,
    );
  }
}

/// Card shell: header, the one collapsed row, and (when expanded) the details.
class _Frame extends StatelessWidget {
  const _Frame({required this.header, required this.row, this.onTap, this.details});

  final Widget header;
  final Widget row;
  final VoidCallback? onTap;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          row,
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: details ?? const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// Header row: 48 px tall in every state (and in the skeleton).
class _Header extends StatelessWidget {
  const _Header({required this.title, this.state});

  final String title;
  final WeatherDataState? state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // At least 48 px; two lines only at large text sizes, so the PHT time stays.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: text.labelLarge?.copyWith(color: context.palette.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (state != null) ...[
            const SizedBox(width: 8),
            DataStateBadge(state: state!, dense: true),
          ],
        ],
      ),
    );
  }
}

/// The one collapsed row: a 24 px leading icon, two lines, a 48 px trailing slot.
class _Row extends StatelessWidget {
  const _Row({
    this.icon,
    this.leading,
    required this.title,
    required this.detail,
    this.trailing,
  });

  final IconData? icon;

  /// Replaces [icon] (24 px), e.g. the alert level mark.
  final Widget? leading;
  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: leading ?? Icon(icon, size: 24, color: context.palette.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(detail, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          SizedBox(
            width: trailing == null ? AppTheme.minTarget : null,
            height: AppTheme.minTarget,
            child: trailing,
          ),
        ],
      ),
    );
  }
}

String _eventLine(OfficialAlert a) {
  final kind = a.subtype.isNotEmpty ? a.subtype : a.event;
  final sentence = kind.isEmpty ? 'Alert' : kind[0].toUpperCase() + kind.substring(1).toLowerCase();
  return [
    sentence,
    if (a.validUntil != null) 'until ${formatPhtTime(a.validUntil!)}',
    if (a.matchedAreas.isNotEmpty) a.matchedAreas.first.name,
  ].join(' · ');
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.more, required this.expanded});

  final OfficialAlert alert;
  final int more;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final detail = '${_eventLine(alert)}${more > 0 ? ' · $more more' : ''}';
    return Semantics(
      button: true,
      expanded: expanded,
      label:
          'Official alert from ${alert.issuer}: ${alert.headline}. $detail. '
          '${expanded ? 'Hide' : 'Show'} the full alert text.',
      excludeSemantics: true,
      child: _Row(
        leading: AlertLevelMark(level: alertLevelOf(alert)),
        title: alert.headline,
        detail: detail,
        // A visible word as well as the chevron, so the row reads as openable.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Hide' : 'Details',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: context.palette.accent),
            ),
            const SizedBox(width: 2),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: context.palette.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.state, required this.checkedAt});

  final WeatherDataState state;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    // "No alerts" is said only when the backend's check is current; otherwise
    // the panel says the check is old or failed, never that all is clear.
    // In a saved copy a Current check is old by now: say so, never all clear.
    final shown = claimsLiveInSavedCopy(context, state) ? WeatherDataState.stale : state;
    final (icon, title, detail) = switch (shown) {
      WeatherDataState.current => (
        Icons.campaign_outlined,
        'No official alerts for this venue',
        'PAGASA alerts appear here as issued.',
      ),
      WeatherDataState.stale || WeatherDataState.updating => (
        Icons.history,
        'No alerts in the last check',
        checkedAt == null
            ? 'PAGASA hasn’t been checked again yet.'
            : 'Last checked ${formatPhtDateTime(checkedAt!)}. Newer alerts may exist.',
      ),
      WeatherDataState.missing || WeatherDataState.unavailable => (
        Icons.cloud_off,
        'Official alerts unavailable',
        'Pitchy couldn’t check PAGASA. Check PAGASA directly.',
      ),
    };
    return Semantics(
      container: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: _Row(icon: icon, title: title, detail: detail),
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.failure, this.onRetry});

  final ApiFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final m = describeFailure(failure);
    return _Row(
      icon: Icons.error_outline,
      title: 'Couldn’t load official alerts',
      detail: m.title,
      trailing: m.canRetry && onRetry != null
          ? TextButton(onPressed: onRetry, child: const Text('Try again'))
          : null,
    );
  }
}

/// Every alert in full, as issued, plus the backend's label.
class _AlertDetails extends StatelessWidget {
  const _AlertDetails({required this.alerts});

  final VenueAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;

    // At large text sizes the 88 px label column crowds; stack label over value.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    Widget field(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: text.bodySmall),
                Text(v, style: text.bodyMedium),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 88, child: Text(k, style: text.bodySmall)),
                Expanded(child: Text(v, style: text.bodyMedium)),
              ],
            ),
    );

    final cyclones = alerts.activeTropicalCyclones;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in bySeverity(alerts.alerts)) ...[
            const Divider(),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: AlertLevelPill(alert: a),
            ),
            const SizedBox(height: 6),
            Text(a.headline, style: text.titleSmall),
            const SizedBox(height: 6),
            // Untrusted source text: plain Text only, never parsed.
            Text(a.message, style: text.bodyMedium),
            const SizedBox(height: 8),
            field('Issued by', a.issuer),
            if (a.issuedAt != null) field('Issued', formatPhtDateTime(a.issuedAt!)),
            if (a.validUntil != null) field('Valid until', formatPhtDateTime(a.validUntil!)),
            if (a.matchedAreas.isNotEmpty)
              field('Areas', a.matchedAreas.map((x) => x.name).join(', ')),
            const SizedBox(height: 6),
          ],
          if (cyclones != null && cyclones > 0) ...[
            const Divider(),
            const SizedBox(height: 8),
            field('Cyclones', '$cyclones active tropical cyclone${cyclones == 1 ? '' : 's'}'),
          ],
          const Divider(),
          const SizedBox(height: 8),
          Text(
            alerts.label ?? 'Official information, shown as issued. Not a Pitchy classification.',
            style: text.bodySmall?.copyWith(color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Stands in for [AlertsPanel] with the same header and row boxes.
class AlertsPanelSkeleton extends StatelessWidget {
  const AlertsPanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SkeletonPulse(
      label: 'Loading official alerts',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: AppTheme.minTarget,
                child: Row(
                  children: [
                    Expanded(child: SkeletonLine(style: text.labelLarge, widthFactor: 0.5)),
                    const SizedBox(width: 8),
                    SkeletonBox(width: 64, height: DataStateBadge.denseHeight(context), radius: 99),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
                child: Row(
                  children: [
                    const SkeletonBox(width: 24, height: 24, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLine(style: text.titleSmall, widthFactor: 0.7),
                          const SizedBox(height: 2),
                          SkeletonLine(style: text.bodySmall, widthFactor: 0.5),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.minTarget, height: AppTheme.minTarget),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
