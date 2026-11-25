import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pht_time.dart';
import '../../shared/models/conversation.dart';
import '../../shared/models/match.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';
import '../../shared/widgets/retry_at.dart';
import '../../shared/widgets/skeletons.dart';
import 'chat_controller.dart';
import 'chat_reply.dart';

/// PitChyAT (P-14): questions about the active match's conditions and the
/// approved guidance, or, without a match, general questions answered from the
/// approved guidance only (Task A, `POST /conversation`). Replies are the backend's, shown as plain text. The
/// agent explains; it is never the safety authority.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, this.clock});

  /// For tests; the device clock otherwise.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final match = AppScope.of(context).match;
    return ListenableBuilder(
      listenable: match,
      builder: (context, _) => switch (match.active) {
        Loading() => const _Frame(child: LoadingState(label: 'Loading your match')),
        Failed(:final failure) => _Frame(
          child: ErrorState(failure: failure, onRetry: match.restore),
        ),
        Loaded(value: null) => _Chat(key: const ValueKey('general'), match: null, clock: clock),
        Loaded(:final value?) => _Chat(key: ValueKey(value.id), match: value, clock: clock),
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PitchyTopBar(title: 'PitChyAT'),
    body: child,
  );
}

/// Readable measure on wide windows.
const _maxWidth = 720.0;

double _sidePadding(BuildContext context) =>
    ((MediaQuery.sizeOf(context).width - _maxWidth) / 2).clamp(16, double.infinity);

/// One conversation. [match] null: general questions only; it is replaced by a
/// fresh match conversation once a match is set up.
class _Chat extends StatefulWidget {
  const _Chat({super.key, required this.match, this.clock});

  final MatchContext? match;
  final DateTime Function()? clock;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  ChatController? _chatOrNull;
  ChatController get _chat => _chatOrNull!;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  int _seen = 0;

  /// False until the user presses Start on the entry screen (each time the
  /// tab opens with no conversation yet).
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chatOrNull != null) return;
    final scope = AppScope.of(context);
    _chatOrNull = ChatController(
      api: scope.api,
      session: scope.chatSession,
      preferences: scope.preferences,
      matchContextId: widget.match?.id,
      clock: widget.clock,
    )..addListener(_followNewEntries);
  }

  @override
  void dispose() {
    _chatOrNull
      ?..removeListener(_followNewEntries)
      ..dispose();
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Keeps the newest message in view when one arrives.
  void _followNewEntries() {
    final count = _chat.entries.length + (_chat.sending ? 1 : 0);
    if (count == _seen) return;
    _seen = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final end = _scroll.position.maxScrollExtent;
      if (reduce) {
        _scroll.jumpTo(end);
      } else {
        unawaited(
          _scroll.animateTo(
            end,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (!_chat.canSend || !ChatController.isValidQuestion(text)) return;
    _input.clear();
    unawaited(_chat.send(text));
  }

  void _useStarter(String question) {
    _input
      ..text = question
      ..selection = TextSelection.collapsed(offset: question.length);
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PitchyTopBar(title: 'PitChyAT'),
    body: ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        final entries = _chat.entries;
        if (!_started && entries.isEmpty && !_chat.sending) {
          return _EntryScreen(
            role: _chat.role,
            onRole: _chat.setRole,
            match: widget.match,
            onStart: () => setState(() => _started = true),
          );
        }
        return Column(
          children: [
            _AgentNotice(match: widget.match),
            Expanded(
              child: entries.isEmpty && !_chat.sending
                  ? _Welcome(
                      questions: _chat.isGeneral ? generalStarterQuestions : starterQuestions,
                      onStarter: _useStarter,
                    )
                  : ListView(
                      controller: _scroll,
                      padding: EdgeInsets.symmetric(
                        horizontal: _sidePadding(context),
                        vertical: 16,
                      ),
                      children: [
                        for (final e in entries)
                          switch (e) {
                            UserQuestion() => _UserBubble(
                              key: ValueKey('q${e.id}'),
                              question: e,
                              canResend: _chat.canSend,
                              onResend: () => unawaited(_chat.resend(e)),
                            ),
                            BotReply() => _BotBubble(key: ValueKey('r${e.id}'), reply: e.response),
                          },
                        if (_chat.sending) const _Thinking(),
                      ],
                    ),
            ),
            _Composer(chat: _chat, input: _input, focus: _inputFocus, onSend: _send),
          ],
        );
      },
    ),
  );
}

/// Always visible above the conversation: what PitChyAT is, and what it isn't.
class _AgentNotice extends StatelessWidget {
  const _AgentNotice({required this.match});

  /// Null: general questions, said here with a way to set up a match.
  final MatchContext? match;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      padding: EdgeInsets.symmetric(horizontal: _sidePadding(context), vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: palette.inkMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI explanations, not official decisions. The Safety tab and your match '
                  'officials decide.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 2),
                if (match case final m?)
                  Text(
                    'About ${m.venue.name}, kickoff ${formatPhtDateTime(m.kickoffAt)}',
                    style: text.bodySmall?.copyWith(color: palette.inkMuted),
                  )
                else ...[
                  Text(
                    'No match selected: general guidance from approved documents only, '
                    'not about current conditions.',
                    style: text.bodySmall?.copyWith(color: palette.ink),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => context.push(Routes.matchSetup),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        minimumSize: const Size(48, 40),
                      ),
                      child: const Text('Set up a match'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed app text, not AI output. They only fill the input; the user sends.
const starterQuestions = [
  'Do we need cooling breaks for this match?',
  'What does the current heat level mean for players?',
  'What should we do if lightning is detected nearby?',
];

/// Fixed app text for the general chat (no match): rules questions only.
const generalStarterQuestions = [
  'When are cooling breaks used?',
  'What should we do if lightning is near?',
  'What does each heat level mean?',
];

class _Welcome extends StatelessWidget {
  const _Welcome({required this.questions, required this.onStarter});

  final List<String> questions;
  final ValueChanged<String> onStarter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: _sidePadding(context), vertical: 20),
      children: [
        Text('Try asking', style: text.titleSmall),
        const SizedBox(height: 8),
        for (final q in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _StarterButton(question: q, onTap: () => onStarter(q)),
          ),
      ],
    );
  }
}

/// What the user sees when they open PitChyAT: who's asking, and which match
/// the questions are about. The match part only appears once a match is set
/// up; the stadium comes from it. Without a match, Start chatting opens the
/// general chat and Set up a match stays on offer for current conditions.
class _EntryScreen extends StatelessWidget {
  const _EntryScreen({
    required this.role,
    required this.onRole,
    required this.match,
    required this.onStart,
  });

  final ConversationRole? role;
  final ValueChanged<ConversationRole> onRole;
  final MatchContext? match;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final m = match;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome to PitChyAT',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                m != null
                    ? 'Ask about the weather and the approved safety guidance for your match. '
                          'Answers are AI explanations, not official decisions.'
                    : 'Ask general questions about the approved safety guidance. '
                          'Answers are AI explanations, not official decisions.',
                style: text.bodyMedium?.copyWith(color: palette.inkMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text('What role are you?', style: text.titleSmall),
              const SizedBox(height: 8),
              DropdownMenu<ConversationRole>(
                key: const ValueKey('role-menu'),
                expandedInsets: EdgeInsets.zero,
                hintText: 'Select your role',
                initialSelection: role,
                requestFocusOnTap: false,
                onSelected: (r) {
                  if (r != null) onRole(r);
                },
                dropdownMenuEntries: [
                  for (final r in ConversationRole.values)
                    DropdownMenuEntry(value: r, label: r.label),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Only changes how answers are worded. It isn’t an account.',
                style: text.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: 24),
              if (m != null) ...[
                Text('Your match', style: text.titleSmall),
                const SizedBox(height: 8),
                _MatchSummary(match: m),
                const SizedBox(height: 32),
                _StartButton(role: role, onStart: onStart),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border.all(color: palette.hairline),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: palette.inkMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No match set up yet. You can ask general questions about the '
                          'approved guidance. For advice about current conditions, set up a '
                          'match.',
                          style: text.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _StartButton(role: role, onStart: onStart),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push(Routes.matchSetup),
                  icon: const Icon(Icons.add),
                  label: const Text('Set up a match'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.role, required this.onStart});

  final ConversationRole? role;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: role == null ? null : onStart,
    icon: const Icon(Icons.forum_outlined),
    label: Text(role == null ? 'Choose your role to start' : 'Start chatting'),
  );
}

class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.match});

  final MatchContext match;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.hairline),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Row(
        children: [
          Icon(Icons.stadium_outlined, size: 22, color: palette.inkMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.venue.name, style: text.bodyLarge),
                Text(
                  'Kickoff ${formatPhtDateTime(match.kickoffAt)}',
                  style: text.bodySmall?.copyWith(color: palette.inkMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Same as the dashboard's Change match: the form starts filled in.
              AppScope.of(context).match.draftFromActive();
              context.push(Routes.matchSetup);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// A starter question as a full-width, wrapping button (a chip would cut long
/// questions off on phones).
class _StarterButton extends StatelessWidget {
  const _StarterButton({required this.question, required this.onTap});

  final String question;

  /// Null until a role is chosen (the input is off until then).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.hairline),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: enabled ? palette.accent : palette.inkMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: enabled ? palette.ink : palette.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    super.key,
    required this.question,
    required this.canResend,
    required this.onResend,
  });

  final UserQuestion question;
  final bool canResend;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final errorColor = context.safetyColors.requestError;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: SelectableText(
              question.text,
              style: text.bodyLarge?.copyWith(color: palette.onAccent),
            ),
          ),
          const SizedBox(height: 4),
          switch (question.status) {
            QuestionSending() || QuestionAnswered() => Text(
              'As ${question.role.label} · ${formatPhtTime(question.askedAt)}',
              style: text.bodySmall?.copyWith(color: palette.inkMuted),
            ),
            QuestionHeld(:final retryAt) => Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusLine(
                  icon: Icons.hourglass_top,
                  color: palette.ink,
                  text: canResend
                      ? 'Not sent: question limit reached.'
                      : retryAt == null
                      ? 'Not sent: question limit reached. Wait a few minutes.'
                      : 'Not sent: question limit reached. ${tryAgainAtText(retryAt)}',
                ),
                if (canResend) TextButton(onPressed: onResend, child: const Text('Send again')),
              ],
            ),
            QuestionFailed(:final failure) => Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusLine(
                  icon: Icons.error_outline,
                  color: errorColor,
                  text: 'Not sent: ${describeFailure(failure).title.toLowerCase()}.',
                ),
                if (describeFailure(failure).canRetry)
                  TextButton(
                    onPressed: canResend ? onResend : null,
                    child: const Text('Send again'),
                  ),
              ],
            ),
          },
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.ink),
        ),
      ),
    ],
  );
}

/// One icon-led line inside a reply (a limitation, a reference, the notice).
class _ReplyLine extends StatelessWidget {
  const _ReplyLine({
    super.key,
    required this.icon,
    required this.text,
    this.color,
    this.style,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color ?? context.palette.inkMuted),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style ?? Theme.of(context).textTheme.bodySmall)),
      ],
    ),
  );
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({super.key, required this.reply});

  final ChatAnswer reply;

  @override
  Widget build(BuildContext context) {
    final view = ChatReplyView.of(reply);
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: palette.inkMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 24),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'PitChyAT reply',
        child: _ReplyCard(
          children: [
            Row(
              children: [
                Icon(Icons.forum_outlined, size: 16, color: palette.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    view.isAnswer ? 'AI-generated · for ${reply.role.label}' : 'No AI answer',
                    style: text.labelMedium?.copyWith(color: palette.inkMuted),
                  ),
                ),
                Text(formatPhtTime(reply.respondedAt), style: muted),
              ],
            ),
            const SizedBox(height: 8),
            // Untrusted text from the backend: plain text only, never markdown
            // or HTML.
            SelectableText(
              view.text,
              style: text.bodyLarge,
            ),
            // Every general reply (no match) says so, right under the text.
            if (view.generalOnly case final general?) ...[
              const SizedBox(height: 10),
              _ReplyLine(
                key: const ValueKey('general-only'),
                icon: Icons.event_busy_outlined,
                text: general,
                color: palette.ink,
                style: text.bodyMedium,
              ),
            ],
            if (view.limitations.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final l in view.limitations)
                _ReplyLine(icon: Icons.warning_amber, text: l.message, color: palette.ink),
            ],
            if (view.references.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Based on', style: text.labelMedium),
              const SizedBox(height: 4),
              for (final g in view.references)
                _ReplyLine(
                  icon: Icons.menu_book_outlined,
                  text: [
                    '${g.title} (${g.authority}, ${g.version})',
                    if (g.sections.isNotEmpty) g.sections.join('; '),
                  ].join(' · '),
                ),
            ],
            const SizedBox(height: 10),
            Divider(height: 1, color: palette.hairline),
            const SizedBox(height: 8),
            _ReplyLine(
              icon: Icons.info_outline,
              text: view.notAuthority,
              color: palette.ink,
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border.all(color: context.palette.hairline),
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
    ),
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

/// Reply placeholder while the question is with the server. After a few
/// seconds it says why it can be slow (cold start, up to about 40 s).
class _Thinking extends StatefulWidget {
  const _Thinking();

  static const slowAfter = Duration(seconds: 6);

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_Thinking.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 24),
      child: _ReplyCard(
        children: [
          Text(
            'PitChyAT is answering…',
            style: text.labelMedium?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: 8),
          SkeletonPulse(
            label: 'PitChyAT is answering',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(style: text.bodyLarge, widthFactor: 0.9),
                SkeletonLine(style: text.bodyLarge, widthFactor: 0.75),
                SkeletonLine(style: text.bodyLarge, widthFactor: 0.5),
              ],
            ),
          ),
          if (_slow) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                'Still working. The server may be starting up; this can take up to 40 seconds.',
                style: text.bodySmall?.copyWith(color: palette.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.chat,
    required this.input,
    required this.focus,
    required this.onSend,
  });

  final ChatController chat;
  final TextEditingController input;
  final FocusNode focus;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final role = chat.role;
    final waitUntil = chat.waitUntil;
    final hint = role == null
        ? 'Choose who’s asking first'
        : waitUntil != null
        ? 'You can ask again at ${formatPhtTime(waitUntil)}'
        : chat.isGeneral
        ? 'Ask a general question'
        : 'Ask about this match';
    final side = _sidePadding(context);
    return Material(
      color: palette.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.hairline)),
          ),
          padding: EdgeInsets.fromLTRB(side, 4, side, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The held question says when to try again; the input hint
              // repeats only the time, so the wait isn't announced twice.
              _RolePicker(role: role, onRole: chat.setRole),
              ValueListenableBuilder(
                valueListenable: input,
                builder: (context, value, _) {
                  final ready = chat.canSend && ChatController.isValidQuestion(value.text);
                  final length = value.text.length;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: CallbackShortcuts(
                          // Enter sends on Windows; Shift+Enter adds a line.
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.enter): () {
                              if (ready) onSend();
                            },
                          },
                          child: TextField(
                            controller: input,
                            focusNode: focus,
                            enabled: role != null && waitUntil == null,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(
                                ConversationRequest.maxQuestionLength,
                              ),
                            ],
                            decoration: InputDecoration(
                              hintText: hint,
                              counterText: length > ConversationRequest.maxQuestionLength - 200
                                  ? '$length / ${ConversationRequest.maxQuestionLength}'
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send question',
                        constraints: const BoxConstraints.tightFor(
                          width: AppTheme.minTarget,
                          height: AppTheme.minTarget,
                        ),
                        onPressed: ready ? onSend : null,
                        icon: chat.sending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.onRole});

  final ConversationRole? role;
  final ValueChanged<ConversationRole> onRole;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ConversationRole>(
    tooltip: 'Change who’s asking',
    initialValue: role,
    onSelected: onRole,
    itemBuilder: (context) => [
      for (final r in ConversationRole.values) PopupMenuItem(value: r, child: Text(r.label)),
    ],
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 18, color: context.palette.inkMuted),
          const SizedBox(width: 6),
          Text(
            role == null ? 'Who’s asking?' : 'Asking as ${role!.label}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );
}
