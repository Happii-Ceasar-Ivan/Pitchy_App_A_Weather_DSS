import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/routing/app_router.dart';
import '../../core/routing/app_shell.dart';
import '../../core/state/loadable.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/pht_time.dart';
import '../../shared/models/conversation.dart';
import '../../shared/models/match.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import '../../shared/widgets/request_states.dart';
import '../../shared/widgets/retry_at.dart';
import '../../shared/widgets/skeletons.dart';
import 'chat_controller.dart';
import 'chat_reply.dart';

/// Ask Pitchy (P-22, was Ask Pitchy under P-14): questions about the active match's conditions and the
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
    appBar: const PitchyTopBar(title: 'Ask Pitchy'),
    body: child,
  );
}

/// Readable measure on wide windows.
const _maxWidth = 720.0;

/// Side padding that centres the [_maxWidth] column in the chat's own pane
/// ([width]: the pane, not the window, so the rail is left out).
double _sideFor(double width) => ((width - _maxWidth) / 2).clamp(16, double.infinity);

/// Phones (no rail): the notice is one line and the role picker shares the
/// input's row, so the conversation keeps most of the height (F4 P2).
bool _isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < AppShell.railBreakpoint;

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

  /// Replies that arrived during this session and have not played their cue yet.
  /// History never enters this set; each reply plays its cue once.
  final _arrived = <int>{};
  int _lastReplyId = -1;

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
    final entries = _chat.entries;
    // A reply replaces the "thinking" row, so the count can stay the same:
    // a new reply also scrolls, so it (and its cue) is always in view.
    var newReply = false;
    if (entries.isNotEmpty && entries.last is BotReply) {
      final id = entries.last.id;
      if (id > _lastReplyId) {
        _lastReplyId = id;
        _arrived
          ..clear()
          ..add(id);
        newReply = true;
      }
    }
    final count = entries.length + (_chat.sending ? 1 : 0);
    if (count == _seen && !newReply) return;
    _seen = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final motion = PitchyMotion.of(context);
      final end = _scroll.position.maxScrollExtent;
      if (motion.reduced) {
        _scroll.jumpTo(end);
      } else {
        unawaited(_scroll.animateTo(end, duration: motion.scroll, curve: PitchyMotion.enter));
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
    appBar: const PitchyTopBar(title: 'Ask Pitchy'),
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
        return LayoutBuilder(
          builder: (context, pane) {
            final side = _sideFor(pane.maxWidth);
            final compact = _isCompact(context);
            final empty = entries.isEmpty && !_chat.sending;
            // Short pane for the text size (a 640 px phone at 2.0x): the notice
            // scrolls with the content instead of pinning space the chat needs.
            final shortPane = pane.maxHeight < 360 * MediaQuery.textScalerOf(context).scale(1);
            final inlineNotice = empty || shortPane;
            final notice = _AgentNotice(
              key: const ValueKey('chat-notice'),
              match: widget.match,
              side: side,
              compact: compact,
            );
            return Column(
              children: [
                if (!inlineNotice) notice,
                Expanded(
                  child: entries.isEmpty && !_chat.sending
                      ? _Welcome(
                          questions: _chat.isGeneral ? generalStarterQuestions : starterQuestions,
                          onStarter: _useStarter,
                          side: side,
                          // Before the first question the notice scrolls with the
                          // content, so a small screen at large text never overflows.
                          header: notice,
                        )
                      : ListView(
                          controller: _scroll,
                          padding: EdgeInsets.only(
                            top: shortPane ? 0 : PitchySpace.lg,
                            bottom: PitchySpace.lg,
                          ),
                          children: [
                            if (shortPane) notice,
                            for (final e in entries)
                              Padding(
                                key: ValueKey('entry${e.id}'),
                                padding: EdgeInsets.symmetric(horizontal: side),
                                child: switch (e) {
                                  UserQuestion() => _UserBubble(
                                    key: ValueKey('q${e.id}'),
                                    question: e,
                                    canResend: _chat.canSend,
                                    onResend: () => unawaited(_chat.resend(e)),
                                  ),
                                  BotReply() => _ArrivalCue(
                                    key: ValueKey('arrive${e.id}'),
                                    // Only the newest reply, once.
                                    play: e.id == _lastReplyId && _arrived.remove(e.id),
                                    child: _BotBubble(
                                      key: ValueKey('r${e.id}'),
                                      reply: e.response,
                                    ),
                                  ),
                                },
                              ),
                            if (_chat.sending)
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: side),
                                child: const _Thinking(),
                              ),
                          ],
                        ),
                ),
                _Composer(
                  key: const ValueKey('chat-composer'),
                  chat: _chat,
                  input: _input,
                  focus: _inputFocus,
                  onSend: _send,
                  side: side,
                  compact: compact,
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

/// Always visible above the conversation: what Ask Pitchy is, and what it isn't.
/// It can be collapsed to the safety line alone; that line never hides.
class _AgentNotice extends StatefulWidget {
  const _AgentNotice({
    super.key,
    required this.match,
    required this.side,
    required this.compact,
  });

  /// Null: general questions, said here with a way to set up a match.
  final MatchContext? match;
  final double side;

  /// Phones: the short safety line. Every reply still ends with the full
  /// "follow the assessment and your match officials" line.
  final bool compact;

  @override
  State<_AgentNotice> createState() => _AgentNoticeState();
}

class _AgentNoticeState extends State<_AgentNotice> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final side = widget.side;
    final compact = widget.compact;
    final palette = context.palette;
    // The whole notice is the hide/show target (at least 48 px tall), so the
    // safety line keeps its width; the arrow is only the visual cue.
    return Material(
      color: palette.surface,
      shape: Border(bottom: BorderSide(color: palette.hairline)),
      child: Tooltip(
        message: _collapsed ? 'Show details' : 'Hide details',
        child: InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: double.infinity),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: side,
                vertical: compact ? PitchySpace.sm : PitchySpace.md,
              ),
              child: _body(context, match, compact),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MatchContext? match, bool compact) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: palette.inkMuted, size: 20),
        // 8 + a 16 px arrow: the phone safety line still fits on one line at 390 px.
        const SizedBox(width: PitchySpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact
                    ? 'AI explanations, not decisions. Officials decide.'
                    : 'AI explanations, not official decisions. The Safety tab and your '
                          'match officials decide.',
                style: text.bodyMedium,
              ),
              if (_collapsed)
                const SizedBox.shrink()
              else if (match case final m?) ...[
                const SizedBox(height: PitchySpace.xxs),
                Text(
                  'About ${m.venue.name}, kickoff ${formatPhtDateTime(m.kickoffAt)}',
                  style: text.bodySmall?.copyWith(color: palette.inkMuted),
                ),
              ] else ...[
                const SizedBox(height: PitchySpace.xxs),
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
        const SizedBox(width: PitchySpace.xs),
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: PitchySpace.xxs),
            child: Icon(
              _collapsed ? Icons.expand_more : Icons.expand_less,
              color: palette.inkMuted,
              size: 16,
            ),
          ),
        ),
      ],
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
  const _Welcome({
    required this.questions,
    required this.onStarter,
    required this.side,
    required this.header,
  });

  final List<String> questions;
  final Widget header;
  final ValueChanged<String> onStarter;
  final double side;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        header,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side, vertical: PitchySpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Try asking', style: text.titleSmall),
              const SizedBox(height: PitchySpace.sm),
              for (final q in questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: PitchySpace.sm),
                  child: _StarterButton(question: q, onTap: () => onStarter(q)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the user sees when they open Ask Pitchy: who's asking, and which match
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
        padding: const EdgeInsets.symmetric(horizontal: PitchySpace.xl, vertical: PitchySpace.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome to Ask Pitchy',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PitchySpace.sm),
              Text(
                m != null
                    ? 'Ask about the weather and the approved safety guidance for your match. '
                          'Answers are AI explanations, not official decisions.'
                    : 'Ask general questions about the approved safety guidance. '
                          'Answers are AI explanations, not official decisions.',
                style: text.bodyMedium?.copyWith(color: palette.inkMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PitchySpace.xxl),
              ExcludeSemantics(child: Text('What role are you?', style: text.titleSmall)),
              const SizedBox(height: PitchySpace.sm),
              _RoleMenu(role: role, onRole: onRole),
              const SizedBox(height: PitchySpace.sm),
              Text(
                'Only changes how answers are worded. It isn’t an account.',
                style: text.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: PitchySpace.lg),
              // AI providers' free tiers may keep prompts (ai-providers.md).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: PitchySpace.xxs),
                    child: Icon(Icons.privacy_tip_outlined, size: 18, color: palette.inkMuted),
                  ),
                  const SizedBox(width: PitchySpace.sm),
                  Expanded(
                    child: Text(
                      'Don’t type names or other personal details: questions go to an outside AI '
                      'service to write the answer.',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PitchySpace.xl),
              if (m != null) ...[
                Text('Your match', style: text.titleSmall),
                const SizedBox(height: PitchySpace.sm),
                _MatchSummary(match: m),
                const SizedBox(height: PitchySpace.xxl),
                _StartButton(role: role, onStart: onStart),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(PitchySpace.lg),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border.all(color: palette.hairline),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: palette.inkMuted),
                      const SizedBox(width: PitchySpace.md),
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
                const SizedBox(height: PitchySpace.xl),
                _StartButton(role: role, onStart: onStart),
                const SizedBox(height: PitchySpace.md),
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

/// The entry screen's role menu. Its semantics carry the visible label and a
/// tap that opens the menu: the plain [DropdownMenu] gave TalkBack no name and
/// no action (found with uiautomator on Android, 2026-11-25).
class _RoleMenu extends StatefulWidget {
  const _RoleMenu({required this.role, required this.onRole});

  final ConversationRole? role;
  final ValueChanged<ConversationRole> onRole;

  @override
  State<_RoleMenu> createState() => _RoleMenuState();
}

class _RoleMenuState extends State<_RoleMenu> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'What role are you?',
    value: widget.role?.label ?? 'None selected',
    hint: 'Only changes how answers are worded',
    onTap: () => _menu.isOpen ? _menu.close() : _menu.open(),
    excludeSemantics: true,
    child: DropdownMenu<ConversationRole>(
      key: const ValueKey('role-menu'),
      menuController: _menu,
      expandedInsets: EdgeInsets.zero,
      hintText: 'Select your role',
      initialSelection: widget.role,
      requestFocusOnTap: false,
      onSelected: (r) {
        if (r != null) widget.onRole(r);
      },
      dropdownMenuEntries: [
        for (final r in ConversationRole.values) DropdownMenuEntry(value: r, label: r.label),
      ],
    ),
  );
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
      padding: const EdgeInsets.fromLTRB(
        PitchySpace.lg,
        PitchySpace.sm,
        PitchySpace.sm,
        PitchySpace.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.hairline),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Row(
        children: [
          Icon(Icons.stadium_outlined, size: 22, color: palette.inkMuted),
          const SizedBox(width: PitchySpace.md),
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
            padding: const EdgeInsets.symmetric(
              horizontal: PitchySpace.lg,
              vertical: PitchySpace.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: enabled ? palette.accent : palette.inkMuted,
                ),
                const SizedBox(width: PitchySpace.md),
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
    final errorColor = context.safetyColors.requestErrorInk;
    return Padding(
      padding: const EdgeInsets.only(bottom: PitchySpace.md, left: PitchySpace.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: PitchySpace.lg,
              vertical: PitchySpace.sm,
            ),
            child: SelectableText(
              question.text,
              style: text.bodyLarge?.copyWith(color: palette.onAccent),
            ),
          ),
          const SizedBox(height: PitchySpace.xs),
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
      const SizedBox(width: PitchySpace.xs),
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
    padding: const EdgeInsets.only(bottom: PitchySpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: PitchySpace.xxs),
          child: Icon(icon, size: 16, color: color ?? context.palette.inkMuted),
        ),
        const SizedBox(width: PitchySpace.sm),
        Expanded(child: Text(text, style: style ?? Theme.of(context).textTheme.bodySmall)),
      ],
    ),
  );
}

/// The cue for a reply that just arrived: opacity 0 to 1 with a small upward
/// rise, once. Reduced motion: a short opacity fade, no movement. It never
/// changes the child's layout box and adds no semantics.
class _ArrivalCue extends StatefulWidget {
  const _ArrivalCue({super.key, required this.play, required this.child});

  /// Decided when the reply is first built; later rebuilds do not replay it.
  final bool play;
  final Widget child;

  @override
  State<_ArrivalCue> createState() => _ArrivalCueState();
}

class _ArrivalCueState extends State<_ArrivalCue> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curved;
  double _rise = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.play || _controller != null) return;
    final motion = PitchyMotion.of(context);
    _rise = motion.rise;
    final controller = AnimationController(vsync: this, duration: motion.fade)..forward();
    _controller = controller;
    _curved = CurvedAnimation(parent: controller, curve: PitchyMotion.enter);
  }

  @override
  void dispose() {
    _curved?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved;
    if (curved == null) return widget.child;
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, _rise * (1 - curved.value)), child: child),
        child: widget.child,
      ),
    );
  }
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
      padding: const EdgeInsets.only(bottom: PitchySpace.lg, right: PitchySpace.xl),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Ask Pitchy reply',
        child: _ReplyCard(
          children: [
            Row(
              children: [
                Icon(Icons.forum_outlined, size: 16, color: palette.inkMuted),
                const SizedBox(width: PitchySpace.sm),
                Expanded(
                  child: Text(
                    view.isAnswer ? 'AI-generated · for ${reply.role.label}' : 'No AI answer',
                    style: text.labelMedium?.copyWith(color: palette.inkMuted),
                  ),
                ),
                Text(formatPhtTime(reply.respondedAt), style: muted),
              ],
            ),
            const SizedBox(height: PitchySpace.sm),
            // Untrusted text from the backend: plain text only, never markdown
            // or HTML.
            SelectableText(
              view.text,
              style: text.bodyLarge,
            ),
            // Every general reply (no match) says so, right under the text.
            if (view.generalOnly case final general?) ...[
              const SizedBox(height: PitchySpace.md),
              _ReplyLine(
                key: const ValueKey('general-only'),
                icon: Icons.event_busy_outlined,
                text: general,
                color: palette.ink,
                style: text.bodyMedium,
              ),
            ],
            if (view.limitations.isNotEmpty) ...[
              const SizedBox(height: PitchySpace.md),
              for (final l in view.limitations)
                _ReplyLine(
                  icon: Icons.warning_amber,
                  text: l.message,
                  color: palette.ink,
                  style: text.bodyMedium,
                ),
            ],
            if (view.references.isNotEmpty) ...[
              const SizedBox(height: PitchySpace.md),
              Text('Based on', style: text.labelMedium),
              const SizedBox(height: PitchySpace.xs),
              for (final g in view.references)
                _ReplyLine(
                  icon: Icons.menu_book_outlined,
                  text: g.line,
                  style: text.bodyMedium?.copyWith(color: palette.inkMuted),
                ),
            ],
            const SizedBox(height: PitchySpace.md),
            Divider(height: 1, color: palette.hairline),
            const SizedBox(height: PitchySpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ReplyLine(
                    icon: Icons.info_outline,
                    text: view.notAuthority,
                    color: palette.ink,
                    style: text.bodyMedium,
                  ),
                ),
                // De-emphasised; the 48 dp target is not allowed to grow the row
                // beyond the notice's own height by more than the button itself.
                IconButton(
                  tooltip: 'Copy reply',
                  icon: Icon(Icons.copy_outlined, size: 20, color: palette.inkMuted),
                  constraints: const BoxConstraints.tightFor(
                    width: AppTheme.minTarget,
                    height: AppTheme.minTarget,
                  ),
                  onPressed: () => _copy(context, view.plainText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _copy(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Reply copied')));
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
    padding: const EdgeInsets.fromLTRB(
      PitchySpace.lg,
      PitchySpace.sm,
      PitchySpace.lg,
      PitchySpace.md,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

/// Reply placeholder while the question is with the server. After a few
/// seconds it says why it can be slow (cold start, up to about a minute).
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
      padding: const EdgeInsets.only(bottom: PitchySpace.lg, right: PitchySpace.xl),
      child: _ReplyCard(
        children: [
          Text(
            'Pitchy is answering…',
            style: text.labelMedium?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: PitchySpace.sm),
          SkeletonPulse(
            label: 'Pitchy is answering',
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
            const SizedBox(height: PitchySpace.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                'Still working. The server may be starting up; this can take up to a minute.',
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
    super.key,
    required this.chat,
    required this.input,
    required this.focus,
    required this.onSend,
    required this.side,
    required this.compact,
  });

  final ChatController chat;
  final TextEditingController input;
  final FocusNode focus;
  final VoidCallback onSend;
  final double side;

  /// Phones: the role picker is a button on the input's row, and the hint
  /// names the role, so the role stays in view without a row of its own.
  final bool compact;

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
    return Material(
      color: palette.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.hairline)),
          ),
          padding: EdgeInsets.fromLTRB(side, compact ? 8 : 4, side, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The held question says when to try again; the input hint
              // repeats only the time, so the wait isn't announced twice.
              if (!compact) _RolePicker(role: role, onRole: chat.setRole),
              ValueListenableBuilder(
                valueListenable: input,
                builder: (context, value, _) {
                  final ready = chat.canSend && ChatController.isValidQuestion(value.text);
                  final length = value.text.length;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (compact) ...[
                        _RolePicker(role: role, onRole: chat.setRole, compact: true),
                        const SizedBox(width: PitchySpace.xs),
                      ],
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
                      const SizedBox(width: PitchySpace.sm),
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
  const _RolePicker({required this.role, required this.onRole, this.compact = false});

  final ConversationRole? role;
  final ValueChanged<ConversationRole> onRole;

  /// Phones: a 48 px chip on the input's row with a short role name and a
  /// caret, so it is seen as a menu (review P1-1); the tooltip and spoken
  /// label give the full name.
  final bool compact;

  /// Short names for the phone chip; the menu and spoken label use the full
  /// [ConversationRole.label].
  static String shortName(ConversationRole r) => switch (r) {
    ConversationRole.matchOfficial => 'Official',
    ConversationRole.medicalStaff => 'Medical',
    _ => r.label,
  };

  List<PopupMenuEntry<ConversationRole>> _items(BuildContext context) => [
    for (final r in ConversationRole.values) PopupMenuItem(value: r, child: Text(r.label)),
  ];

  @override
  Widget build(BuildContext context) => compact
      ? PopupMenuButton<ConversationRole>(
          tooltip: role == null
              ? 'Choose who’s asking'
              : 'Asking as ${role!.label}. Change who’s asking',
          initialValue: role,
          onSelected: onRole,
          itemBuilder: _items,
          constraints: const BoxConstraints(minWidth: 200),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
            padding: const EdgeInsetsDirectional.only(start: PitchySpace.md, end: PitchySpace.xxs),
            decoration: BoxDecoration(
              border: Border.all(color: context.palette.hairline),
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  role == null ? 'Role' : shortName(role!),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        )
      : PopupMenuButton<ConversationRole>(
          tooltip: 'Change who’s asking',
          initialValue: role,
          onSelected: onRole,
          itemBuilder: _items,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_outlined, size: 18, color: context.palette.inkMuted),
                const SizedBox(width: PitchySpace.sm),
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
