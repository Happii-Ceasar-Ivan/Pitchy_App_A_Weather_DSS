import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/errors/api_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../../shared/models/match.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/retry_at.dart';
import '../../shared/widgets/skeletons.dart';
import 'match_controller.dart';

/// How far ahead a kickoff can be picked. A UI input limit only (rulebook law
/// 15); whether forecasts cover the match is always the backend's answer.
const kickoffDaysAhead = 14;

/// Set up a match (F1): one of the two fixed venues (P-07), kickoff date and
/// time in Philippine Time (P-14), optional pitch surface. The form is kept as
/// a draft if the user leaves (rulebook law 4).
class MatchSetupScreen extends StatefulWidget {
  const MatchSetupScreen({super.key});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  bool _triedSubmit = false;
  ApiFailure? _submitError;

  MatchController get _match => AppScope.of(context).match;

  @override
  void initState() {
    super.initState();
    // After the first frame: these notify listeners, which must not happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prepare();
    });
  }

  void _prepare() {
    final m = _match;
    if (m.venues is! Loaded<List<Venue>>) m.loadVenues();
    // Smart default (law 19): today's date in PHT, if no date is chosen yet.
    if (m.draft.date == null) {
      final today = toPhtWallClock(m.now);
      m.updateDraft(m.draft.copyWith(date: DateTime.utc(today.year, today.month, today.day)));
    }
  }

  Future<void> _pickDate() async {
    final m = _match;
    final today = toPhtWallClock(m.now);
    final first = DateTime(today.year, today.month, today.day);
    final current = m.draft.date;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Match date (PHT)',
      initialDate: current == null ? first : DateTime(current.year, current.month, current.day),
      firstDate: first,
      lastDate: first.add(const Duration(days: kickoffDaysAhead)),
    );
    if (picked != null) {
      m.updateDraft(m.draft.copyWith(date: DateTime.utc(picked.year, picked.month, picked.day)));
    }
  }

  Future<void> _pickTime() async {
    final m = _match;
    final picked = await showTimePicker(
      context: context,
      helpText: 'Kickoff time (PHT)',
      initialTime: m.draft.time ?? const TimeOfDay(hour: 15, minute: 0),
    );
    if (picked != null) m.updateDraft(m.draft.copyWith(time: picked));
  }

  Future<void> _submit() async {
    final m = _match;
    setState(() {
      _triedSubmit = true;
      _submitError = null;
    });
    if (m.problems().isNotEmpty) return;
    try {
      await m.submit();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.dashboard);
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _submitError = e);
    }
  }

  String _dateLabel(DateTime d) =>
      formatPhtDateTime(fromPhtWallClock(d.year, d.month, d.day, 12, 0)).split(',').first;

  String _timeLabel(TimeOfDay t) => formatPhtTime(fromPhtWallClock(2000, 1, 1, t.hour, t.minute));

  @override
  Widget build(BuildContext context) {
    final m = _match;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'Set up a match'),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final draft = m.draft;
          final problems = _triedSubmit ? m.problems() : const <DraftProblem>[];
          final width = MediaQuery.sizeOf(context).width;
          return ListView(
            padding: EdgeInsets.symmetric(
              vertical: 16,
              horizontal: ((width - 640) / 2).clamp(16, double.infinity),
            ),
            children: [
              _Section(
                title: 'Venue',
                error: problems.contains(DraftProblem.noVenue) ? 'Choose a venue.' : null,
                child: switch (m.venues) {
                  Loading() => const _VenueSkeleton(),
                  Failed(:final failure) => _InlineFailure(failure: failure, onRetry: m.loadVenues),
                  Loaded(:final value) => RadioGroup<String>(
                    groupValue: draft.venueKey,
                    onChanged: (v) => m.updateDraft(draft.copyWith(venueKey: v)),
                    child: Column(
                      children: [
                        for (final v in value) ...[
                          Card(
                            child: RadioListTile<String>(
                              value: v.scopeKey,
                              title: Text(v.name.split(',').first),
                              subtitle: Text(v.name.split(',').skip(1).join(',').trim()),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                },
              ),
              _Section(
                title: 'Kickoff (Philippine Time, PHT)',
                error: problems.contains(DraftProblem.noDate)
                    ? 'Choose a date.'
                    : problems.contains(DraftProblem.noTime)
                    ? 'Choose a kickoff time.'
                    : problems.contains(DraftProblem.kickoffInPast)
                    ? 'Kickoff has to be later than now.'
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: _PickerField(
                        label: 'Date',
                        value: draft.date == null ? null : _dateLabel(draft.date!),
                        icon: Icons.calendar_today,
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PickerField(
                        label: 'Time',
                        value: draft.time == null ? null : _timeLabel(draft.time!),
                        icon: Icons.schedule,
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Age group',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<AgeGroup>(
                      segments: const [
                        ButtonSegment(value: AgeGroup.senior, label: Text('Senior')),
                        ButtonSegment(
                          value: AgeGroup.youthU20,
                          label: Text('Under-20 or younger'),
                        ),
                      ],
                      selected: {draft.ageGroup},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => m.updateDraft(draft.copyWith(ageGroup: s.single)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chooses which heat levels the safety assessment uses. '
                      'To change it later, set up the match again.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Pitch surface (optional)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in PitchSurface.values)
                          ChoiceChip(
                            label: Text(s.label),
                            selected: draft.surface == s,
                            onSelected: (on) => m.updateDraft(
                              on ? draft.copyWith(surface: s) : draft.copyWith(clearSurface: true),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saved with the match for reference. It doesn’t change any reading.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_submitError != null) ...[
                _InlineFailure(failure: _submitError!, onRetry: _submit),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              RetryAtBuilder(
                retryAt: rateLimitRetryAt(_submitError),
                builder: (context, waiting) => FilledButton.icon(
                  onPressed: m.submitting || waiting ? null : _submit,
                  icon: m.submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(waiting ? Icons.hourglass_top : Icons.check),
                  label: Text(
                    m.submitting
                        ? 'Setting up…'
                        : waiting
                        ? 'Wait until ${formatPhtTime(rateLimitRetryAt(_submitError)!)}'
                        : 'Show conditions',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your choices are kept if you leave this screen.',
                style: text.bodySmall?.copyWith(color: palette.inkMuted),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.error});

  final String title;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: text.titleMedium)),
          const SizedBox(height: 8),
          child,
          if (error != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: context.safetyColors.requestErrorInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      style: text.bodyMedium?.copyWith(color: context.safetyColors.requestErrorInk),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled field that opens a picker. The label stays visible (law 12).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: Icon(icon),
      ),
      isEmpty: value == null,
      child: Text(value ?? '', style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({required this.failure, required this.onRetry});

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final m = describeFailure(failure);
    final retryAt = rateLimitRetryAt(failure);
    final text = Theme.of(context).textTheme;
    return RetryAtBuilder(
      retryAt: retryAt,
      builder: (context, waiting) => _card(context, m, text, retryAt, waiting),
    );
  }

  Widget _card(
    BuildContext context,
    FailureMessage m,
    TextTheme text,
    DateTime? retryAt,
    bool waiting,
  ) {
    final limited = isRateLimited(failure);
    final detail = !limited
        ? m.detail
        : waiting
        ? 'Pitchy’s server is limiting new matches. ${tryAgainAtText(retryAt!)}'
        : retryAt == null
        ? m.detail
        : 'You can try again now.';
    final canRetry = limited ? !waiting : m.canRetry;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.safetyColors.requestErrorInk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, style: text.titleSmall),
                  Text(detail, style: text.bodySmall),
                ],
              ),
            ),
            if (canRetry) TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Two venue rows while the list loads, the same size as the real rows.
class _VenueSkeleton extends StatelessWidget {
  const _VenueSkeleton();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row() => Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const SkeletonBox(width: 20, height: 20, radius: 10),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonLine(style: text.bodyLarge, widthFactor: 0.7),
                    SkeletonLine(style: text.bodyMedium, widthFactor: 0.4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SkeletonPulse(
      label: 'Loading venues',
      child: Column(children: [row(), const SizedBox(height: 8), row(), const SizedBox(height: 8)]),
    );
  }
}
