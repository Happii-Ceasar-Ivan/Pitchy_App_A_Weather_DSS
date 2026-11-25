import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/match.dart';
import '../../shared/models/weather.dart';
import '../../shared/widgets/alerts_panel.dart';
import '../../shared/widgets/data_state_badge.dart';
import '../../shared/widgets/kickoff_strip.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';
import '../../shared/widgets/source_rail.dart';
import '../../shared/widgets/weather_value_card.dart';
import '../match_management/match_controller.dart';
import 'dashboard_controller.dart';
import 'ingest_widgets.dart';
import 'ingestion_controller.dart';

/// Dashboard: the active match's kickoff strip, official alerts, the source
/// rail (with the update action, F2) and the weather cards. Every state and
/// value is the backend's; the app adds none.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final match = AppScope.of(context).match;
    return ListenableBuilder(
      listenable: match,
      builder: (context, _) => switch (match.active) {
        Loading() => const _Frame(
          strip: KickoffStripSkeleton(),
          child: _BoardList(children: _boardSkeleton),
        ),
        // Server unreachable at start: the match from the saved copy (DEC-13);
        // its board then shows the saved weather with the banner.
        Failed(saved: SavedCopy(:final value?)) => _MatchDashboard(
          key: ValueKey(value.id),
          match: value,
        ),
        Failed(:final failure) => _Frame(
          child: ErrorState(failure: failure, onRetry: match.restore),
        ),
        Loaded(value: null) => _Frame(
          child: EmptyState(
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
        ),
        Loaded(:final value?) => _MatchDashboard(key: ValueKey(value.id), match: value),
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.actions = const [], this.strip});

  final Widget child;
  final List<Widget> actions;
  final Widget? strip;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PitchyTopBar(title: 'Dashboard', actions: actions),
    body: Column(
      children: [
        ?strip,
        Expanded(child: child),
      ],
    ),
  );
}

class _MatchDashboard extends StatefulWidget {
  const _MatchDashboard({super.key, required this.match});

  final MatchContext match;

  @override
  State<_MatchDashboard> createState() => _MatchDashboardState();
}

class _MatchDashboardState extends State<_MatchDashboard> {
  late final DashboardController _controller;
  late final IngestionController _ingest;
  late final MatchController _match;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = AppScope.of(context);
    _match = scope.match;
    _controller = DashboardController(
      api: scope.api,
      matchContextId: widget.match.id,
      savedCopies: scope.savedCopies,
    )..addListener(_watchRunningJobs);
    _ingest = IngestionController(
      api: scope.api,
      matchContextId: widget.match.id,
      onFinished: _controller.load,
      onAccepted: _controller.load,
      clock: () => scope.match.now,
    )..addListener(_announce);
    _controller.load();
  }

  /// Jobs the backend reports running for this venue (anyone's, or the
  /// schedule) are followed too, and the board reloads when they finish.
  void _watchRunningJobs() {
    final data = _controller.data;
    if (data is! Loaded<DashboardData> || _controller.refreshing) return;
    _match.serverReachable();
    // Once per backend reply, so "Check again" (a reload) resumes watching but
    // other updates on screen don't.
    if (identical(data.value.status, _watchedStatus)) return;
    _watchedStatus = data.value.status;
    _ingest.watch(data.value.status.activeJobIds);
  }

  WeatherStatus? _watchedStatus;

  /// Success and "already up to date" are brief: a snack bar, then cleared.
  void _announce() {
    final message = switch (_ingest.outcome) {
      IngestUpdated() => 'Weather data updated.',
      IngestNotNeeded() => 'The server says no update is needed.',
      IngestBusy() => 'An update is already running on the server.',
      _ => null,
    };
    if (message == null || !mounted) return;
    _ingest.dismissOutcome();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller.removeListener(_watchRunningJobs);
    _ingest
      ..removeListener(_announce)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _changeMatch() {
    AppScope.of(context).match.draftFromActive();
    context.push(Routes.matchSetup);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_controller, _ingest]),
    builder: (context, _) {
      final alerts = AlertsPanel(alerts: _controller.alerts, onRetry: _controller.retryAlerts);
      return _Frame(
        strip: KickoffStrip(match: widget.match, onChange: _changeMatch),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _controller.refreshing ? null : _controller.load,
          ),
        ],
        child: RefreshIndicator(
          onRefresh: _controller.load,
          child: Stack(
            children: [
              _BoardList(
                children: switch (_controller.data) {
                  Loading() => _boardSkeleton,
                  // DEC-13: the server can't be reached, so the last saved
                  // board shows under the banner. Never labelled live, and
                  // Update stays off until the server answers again.
                  Failed(saved: SavedCopy(:final value, :final savedAt)) => [
                    _SavedCopyBanner(
                      savedAt: savedAt,
                      onRetry: _controller.refreshing ? null : _controller.load,
                    ),
                    const SizedBox(height: 12),
                    AlertsPanel(alerts: _controller.alerts),
                    const SizedBox(height: 12),
                    SavedCopyScope(
                      savedAt: savedAt,
                      child: _Board(
                        rail: SourceRail(
                          sources: value.status.sources,
                          checkedAt: value.status.checkedAt,
                          coverage: value.status.coverage,
                          kickoff: widget.match.kickoffAt,
                          now: AppScope.of(context).match.now,
                          action: const _UpdateOffWhileSaved(),
                        ),
                        cards: WeatherCardGrid(
                          weather: value.weather,
                          kickoff: widget.match.kickoffAt,
                        ),
                      ),
                    ),
                  ],
                  Failed(:final failure) => [
                    // The board's Try again reloads the alerts too: one button.
                    AlertsPanel(alerts: _controller.alerts),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 360,
                      child: ErrorState(failure: failure, onRetry: _controller.load),
                    ),
                  ],
                  Loaded(:final value) => [
                    alerts,
                    const SizedBox(height: 12),
                    _Board(
                      rail: SourceRail(
                        sources: value.status.sources,
                        checkedAt: value.status.checkedAt,
                        coverage: value.status.coverage,
                        kickoff: widget.match.kickoffAt,
                        now: AppScope.of(context).match.now,
                        action: updateAction(
                          context,
                          ingest: _ingest,
                          ingestionNeeded: value.status.ingestionNeeded,
                        ),
                        notice: IngestNotice.shows(_ingest.outcome)
                            ? IngestNotice(
                                outcome: _ingest.outcome!,
                                sources: value.status.sources,
                                // The wait reason stays while the button is held.
                                onDismiss: _ingest.waitUntil == null
                                    ? _ingest.dismissOutcome
                                    : null,
                                onCheckAgain: () {
                                  _ingest.dismissOutcome();
                                  _controller.load();
                                },
                              )
                            : null,
                      ),
                      cards: WeatherCardGrid(
                        weather: value.weather,
                        kickoff: widget.match.kickoffAt,
                      ),
                    ),
                  ],
                },
              ),
              if (_controller.refreshing)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The DEC-13 banner in the board's measure, with "Try again".
class _SavedCopyBanner extends StatelessWidget {
  const _SavedCopyBanner({required this.savedAt, required this.onRetry});

  final DateTime savedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final fg = context.stateColors.of(WeatherDataState.stale).foreground;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: NoticeBanner.savedCopy(
        context,
        savedAt: savedAt,
        action: TextButton(
          style: TextButton.styleFrom(foregroundColor: fg),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ),
    );
  }
}

/// Update, shown but off while a saved copy is on screen: an update needs the
/// server, and the reason is said rather than hiding the button.
class _UpdateOffWhileSaved extends StatelessWidget {
  const _UpdateOffWhileSaved();

  static const reason = 'Update is off while Pitchy can’t reach its server.';

  /// What a screen reader says: touch and keyboard users can't reach the
  /// tooltip, and the banner above gives the visible reason.
  static const spoken = 'Update, unavailable while Pitchy can’t reach its server';

  @override
  Widget build(BuildContext context) => Tooltip(
    message: reason,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      enabled: false,
      label: spoken,
      excludeSemantics: true,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
        onPressed: null,
        icon: const Icon(Icons.sync, size: 18),
        label: const Text('Update'),
      ),
    ),
  );
}

/// The board's loading shape: alerts, then rail and cards.
const _boardSkeleton = <Widget>[AlertsPanelSkeleton(), SizedBox(height: 12), _BoardSkeleton()];

/// Scrollable board, centred with a readable measure on wide windows.
class _BoardList extends StatelessWidget {
  const _BoardList({required this.children});

  final List<Widget> children;

  static const maxWidth = 1100.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        vertical: 16,
        horizontal: ((width - maxWidth) / 2).clamp(16, double.infinity),
      ),
      children: children,
    );
  }
}

/// Phone: rail above the cards. Wide windows: rail beside the cards.
class _Board extends StatelessWidget {
  const _Board({required this.rail, required this.cards});

  final Widget rail;
  final Widget cards;

  static const sideBySide = 900.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= sideBySide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: rail),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: cards),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [rail, const SizedBox(height: 12), cards],
          ),
  );
}

class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) =>
      const _Board(rail: SourceRailSkeleton(), cards: WeatherCardGridSkeleton());
}
