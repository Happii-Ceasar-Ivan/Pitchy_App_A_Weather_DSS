import 'package:material_ui/material_ui.dart';

import '../../core/errors/api_failure.dart';
import '../../shared/models/match.dart';
import '../../shared/models/weather.dart';
import '../../shared/services/mock/fixtures.dart';
import '../../shared/services/mock/mock_pitchy_api.dart';
import '../../shared/widgets/data_state_badge.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';
import '../../shared/widgets/source_rail.dart';
import '../../shared/widgets/weather_value_card.dart';

/// Debug-only review screen: every shared state component, fed by the mock
/// backend's scenarios. All data here is SYNTHETIC.
class StateGalleryScreen extends StatefulWidget {
  const StateGalleryScreen({super.key, this.clock});

  final DateTime Function()? clock;

  @override
  State<StateGalleryScreen> createState() => _StateGalleryScreenState();
}

class _StateGalleryScreenState extends State<StateGalleryScreen> {
  MockScenario _scenario = MockScenario.someStale;
  late final MockPitchyApi _api = MockPitchyApi(
    scenario: _scenario,
    clock: widget.clock,
    latency: Duration.zero,
  );
  Future<(MatchContext, WeatherStatus, ConsolidatedWeather)>? _load;

  DateTime get _now => (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _api.scenario = _scenario;
    setState(() {
      _load = () async {
        final match = await _api.getMatchContext(rizalMemorialId);
        return (
          match,
          await _api.getWeatherStatus(match.id),
          await _api.getWeather(match.id),
        );
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'Component states'),
      body: ListView(
        // Readable measure on wide windows.
        padding: EdgeInsets.symmetric(
          vertical: 16,
          horizontal: ((MediaQuery.sizeOf(context).width - 960) / 2).clamp(16, double.infinity),
        ),
        children: [
          Text('SYNTHETIC mock data for review. Not real conditions.', style: text.bodySmall),
          const SizedBox(height: 12),
          DropdownMenu<MockScenario>(
            label: const Text('Mock backend scenario'),
            initialSelection: _scenario,
            onSelected: (s) {
              if (s == null) return;
              _scenario = s;
              _reload();
            },
            dropdownMenuEntries: [
              for (final s in MockScenario.values) DropdownMenuEntry(value: s, label: s.name),
            ],
          ),
          const SizedBox(height: 16),
          Text('State pills', style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final s in WeatherDataState.values) DataStateBadge(state: s)],
          ),
          const SizedBox(height: 16),
          Text('Banners', style: text.titleMedium),
          const SizedBox(height: 8),
          NoticeBanner.updating(context),
          const SizedBox(height: 8),
          NoticeBanner.savedCopy(context, savedAt: _now.subtract(const Duration(minutes: 40))),
          const SizedBox(height: 16),
          Text('Board (scenario: ${_scenario.name})', style: text.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder(
            future: _load,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 160, child: LoadingState(label: 'Loading weather'));
              }
              if (snap.hasError) {
                final error = snap.error;
                return SizedBox(
                  height: 260,
                  child: ErrorState(
                    failure: error is ApiFailure ? error : const ContractFailure('unknown'),
                    onRetry: _reload,
                  ),
                );
              }
              final (match, status, weather) = snap.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (status.activeJobIds.isNotEmpty) ...[
                    NoticeBanner.updating(context),
                    const SizedBox(height: 8),
                  ],
                  SourceRail(
                    sources: status.sources,
                    checkedAt: status.checkedAt,
                    coverage: status.coverage,
                    kickoff: match.kickoffAt,
                    now: _now,
                  ),
                  const SizedBox(height: 12),
                  WeatherCardGrid(weather: weather, kickoff: match.kickoffAt),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Empty', style: text.titleMedium),
          const SizedBox(
            height: 220,
            child: EmptyState(title: 'No alerts', detail: 'No official alerts for this venue.'),
          ),
          Text('Not available yet (501)', style: text.titleMedium),
          SizedBox(
            height: 220,
            child: ErrorState(
              failure: ApiError.fromEnvelope(501, errorJson('NOT_IMPLEMENTED', 'Not yet.')),
            ),
          ),
        ],
      ),
    );
  }
}
