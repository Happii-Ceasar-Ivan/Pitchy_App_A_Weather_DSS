import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../core/network/pitchy_api.dart';
import '../../core/state/loadable.dart';
import '../../shared/models/assessment.dart';
import '../../shared/models/lightning.dart';

/// What the Safety tab shows for one match: the backend's saved assessment and
/// the live lightning reading. Both come straight from the backend; the app
/// never calculates, classifies or overrides anything (FR-SAF, P-19).
///
/// The two load on their own, so a failed lightning check never hides the
/// assessment and the assessment never waits for the lightning check.
class SafetyController extends ChangeNotifier {
  SafetyController({
    required this.api,
    required this.matchContextId,
    this.refreshEvery = defaultRefresh,
  });

  /// How often the tab refreshes while it is visible and the match is in the
  /// live lightning window (team decision 2026-11-24). The backend calls the
  /// detection source at most once per venue per check interval and saves an
  /// assessment only when it changes, so this adds no database rows of its own.
  static const defaultRefresh = Duration(seconds: 60);

  final PitchyApi api;
  final String matchContextId;
  final Duration refreshEvery;

  Loadable<SafetyAssessment> _assessment = const Loading();
  Loadable<SafetyAssessment> get assessment => _assessment;

  Loadable<VenueLightning> _lightning = const Loading();
  Loadable<VenueLightning> get lightning => _lightning;

  bool _refreshing = false;

  /// True while a refresh runs over data already on screen (no skeleton then).
  bool get refreshing => _refreshing;

  bool _visible = false;
  Timer? _timer;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads both. Data already on screen stays while the refresh runs. A failed
  /// refresh turns the state into the error; the last assessment is then only
  /// available as [notCurrentAssessment], never as current.
  Future<void> load() async {
    if (_assessment is Loaded || _lightning is Loaded) {
      _refreshing = true;
    }
    if (_assessment is! Loaded) _assessment = const Loading();
    if (_lightning is! Loaded) _lightning = const Loading();
    _notify();
    await Future.wait([_loadAssessment(), _loadLightning()]);
    _refreshing = false;
    _notify();
  }

  Future<void> retryAssessment() {
    _assessment = const Loading();
    _notify();
    return _loadAssessment().then((_) => _notify());
  }

  Future<void> retryLightning() {
    _lightning = const Loading();
    _notify();
    return _loadLightning().then((_) => _notify());
  }

  SafetyAssessment? _previous;

  /// The last assessment the backend sent, kept only after a later refresh of
  /// it failed (team decision 2026-11-24). The screen must show it as Not
  /// current with its own "assessed" time, under the error; never as current.
  /// Null while the assessment is loaded, or when there never was one.
  SafetyAssessment? get notCurrentAssessment => _assessment is Failed ? _previous : null;

  Future<void> _loadAssessment() async {
    try {
      final a = await api.getAssessment(matchContextId);
      _previous = a;
      _assessment = Loaded(a);
    } on ApiFailure catch (e) {
      _assessment = Failed(e);
    }
  }

  /// The live-window flag from the last lightning reply that arrived. A failed
  /// check doesn't reset it, so one failed check mid-match never stops the
  /// refresh; the next successful reply sets it again.
  bool _lastInLiveWindow = false;

  Future<void> _loadLightning() async {
    try {
      final l = await api.getLightning(matchContextId);
      _lastInLiveWindow = l.inLiveWindow;
      _lightning = Loaded(l);
    } on ApiFailure catch (e) {
      _lightning = Failed(e);
    }
    _schedule();
  }

  /// The screen reports whether the tab is on screen and the app in front.
  /// Refreshing runs only then.
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _schedule();
  }

  /// True when the last lightning reply said the match is in its live window.
  /// The backend decides the window; the app only reads the flag.
  bool get _inLiveWindow => _lastInLiveWindow;

  bool get autoRefreshing => _timer != null;

  void _schedule() {
    final want = _visible && _inLiveWindow && !_disposed;
    if (want && _timer == null) {
      _timer = Timer.periodic(refreshEvery, (_) {
        if (!_refreshing) unawaited(load());
      });
    } else if (!want && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
