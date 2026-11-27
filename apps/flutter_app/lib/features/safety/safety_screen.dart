import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/errors/api_failure.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/spacing.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/match.dart';
import '../../shared/models/weather.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';
import '../match_management/match_controller.dart';
import 'safety_cards.dart';
import 'safety_controller.dart';
import 'safety_widgets.dart';

/// Safety tab: what the backend's approved rules say for the active match, with
/// the live lightning reading. Everything shown is the backend's (F3 spec); the
/// app never calculates, classifies or rewords it.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final match = AppScope.of(context).match;
    return ListenableBuilder(
      listenable: match,
      builder: (context, _) => switch (match.active) {
        Loading() => const _Frame(child: _SafetyList(children: [SafetySkeleton()])),
        // Server unreachable at start: the saved match (DEC-13).
        Failed(saved: SavedCopy(:final value?)) => _MatchSafety(
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
            detail: 'Choose a venue and kickoff time to see the safety assessment for your match.',
            action: FilledButton.icon(
              onPressed: () => context.push(Routes.matchSetup),
              icon: const Icon(Icons.add),
              label: const Text('Set up a match'),
            ),
          ),
        ),
        Loaded(:final value?) => _MatchSafety(key: ValueKey(value.id), match: value),
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.actions = const []});

  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PitchyTopBar(title: 'Safety', actions: actions),
    body: child,
  );
}

/// Scrollable single column, centred with a readable measure.
class _SafetyList extends StatelessWidget {
  const _SafetyList({required this.children});

  final List<Widget> children;

  static const maxWidth = 720.0;

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

class _MatchSafety extends StatefulWidget {
  const _MatchSafety({super.key, required this.match});

  final MatchContext match;

  @override
  State<_MatchSafety> createState() => _MatchSafetyState();
}

class _MatchSafetyState extends State<_MatchSafety> {
  SafetyController? _controller;
  late MatchController _match;
  late final AppLifecycleListener _lifecycle;

  /// A live assessment means the server is back: refresh a saved match too.
  void _confirmOnline() {
    if (_controller?.assessment is Loaded) _match.serverReachable();
  }

  bool _appResumed = true;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    final state = SchedulerBinding.instance.lifecycleState;
    _appResumed = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        _appResumed = s == AppLifecycleState.resumed;
        _syncVisibility();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _match = scope.match;
    _controller ??= SafetyController(
      api: scope.api,
      matchContextId: widget.match.id,
      savedCopies: scope.savedCopies,
      clock: () => scope.match.now,
    )..addListener(_confirmOnline);
    _syncVisibility();
  }

  /// Visible = this tab is the one on screen (go_router's shell turns tickers
  /// off for hidden branches) and the app is in front. Loads the first time it
  /// becomes visible; the controller refreshes only while visible.
  void _syncVisibility() {
    final c = _controller;
    if (c == null || !mounted) return;
    final visible = TickerMode.valuesOf(context).enabled && _appResumed;
    if (visible && !_loadedOnce) {
      _loadedOnce = true;
      Future.microtask(() {
        if (mounted) c.load();
      });
    }
    c.setVisible(visible);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller
      ?..removeListener(_confirmOnline)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    final now = AppScope.of(context).match.now;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _Frame(
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: c.refreshing ? null : c.load,
          ),
        ],
        child: RefreshIndicator(
          onRefresh: c.load,
          child: _SafetyList(
            children: [
              switch (c.assessment) {
                Loading() => const SafetySkeleton(),
                Failed(:final failure) when c.notCurrentAssessment != null => _Loaded(
                  assessment: c.notCurrentAssessment!,
                  controller: c,
                  now: now,
                  failure: failure,
                ),
                Failed(:final failure) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: ErrorState(failure: failure, onRetry: c.retryAssessment),
                    ),
                    const SizedBox(height: safetyCardGap),
                    LightningOnlyCard(
                      lightning: c.lightning,
                      now: now,
                      onRetry: c.retryLightning,
                    ),
                    const SizedBox(height: safetyCardGap),
                    const SafetyFooter(),
                  ],
                ),
                Loaded(:final value) => _Loaded(assessment: value, controller: c, now: now),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.assessment,
    required this.controller,
    required this.now,
    this.failure,
  });

  final SafetyAssessment assessment;
  final SafetyController controller;
  final DateTime now;

  /// Set when this is the last assessment, shown after a failed refresh.
  final ApiFailure? failure;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final notCurrent = failure != null;
    String? draftMessage;
    for (final l in a.limitations) {
      if (l.code == rulesNotApprovedCode) draftMessage = l.message;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.savedCopyAt case final savedAt?) ...[
          // DEC-13: from the device, server unreachable. Lightning stays live
          // only and shows its own state below.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: NoticeBanner.savedCopy(
              context,
              savedAt: savedAt,
              tries: controller.savedCopyTries,
              lastTriedAt: controller.lastTriedAt,
              action: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.stateColors.of(WeatherDataState.stale).foreground,
                ),
                onPressed: controller.retryAssessment,
                child: const Text('Try again'),
              ),
            ),
          ),
          const SizedBox(height: safetyCardGap),
        ] else if (failure != null) ...[
          AssessmentFailureBanner(failure: failure!, onRetry: controller.retryAssessment),
          const SizedBox(height: safetyCardGap),
        ],
        if (!a.rulesApproved) ...[
          RulesBanner(message: draftMessage),
          const SizedBox(height: safetyCardGap),
        ],
        // From the device: the banner already says not live and when, and the
        // card gives the assessed time; the pills still say Not current.
        if (notCurrent && controller.savedCopyAt == null) ...[
          NotCurrentLine(assessedAt: a.assessedAt, now: now),
          const SizedBox(height: safetyCardGap),
        ],
        SafetyHeaderCard(assessment: a, now: now, refreshing: controller.refreshing),
        for (final indicator in a.indicators) ...[
          const SizedBox(height: safetyCardGap),
          HazardCard(
            key: ValueKey(indicator.hazard),
            indicator: indicator,
            now: now,
            assessedAt: a.assessedAt,
            lightning: controller.lightning,
            onRetryLightning: controller.retryLightning,
            rulesApproved: a.rulesApproved,
            notCurrent: notCurrent,
          ),
        ],
        if (a.officialNotices.isNotEmpty) ...[
          const SizedBox(height: safetyCardGap),
          OfficialNoticesCard(notices: a.officialNotices, now: now),
        ],
        const SizedBox(height: PitchySpace.xl),
        SafetyFooter(ruleVersion: a.ruleVersion),
      ],
    );
  }
}
