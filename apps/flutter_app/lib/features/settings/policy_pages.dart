import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/pitchy_top_bar.dart';

/// One headed part of a policy page.
@immutable
class PolicySection {
  const PolicySection(this.heading, {this.paragraphs = const [], this.bullets = const []});

  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;
}

@immutable
class PolicyPage {
  const PolicyPage({
    required this.title,
    required this.intro,
    required this.updated,
    required this.sections,
  });

  final String title;
  final String intro;
  final String updated;
  final List<PolicySection> sections;
}

/// The Privacy policy and Safety disclaimer, approved by the user on
/// 2026-11-26 (P-25; draft in docs/frontend/drafts/). Fixed app text, never
/// downloaded. The facts were checked against the backend: the raw IP is
/// never stored (HMAC only, `ip_rate_limits`, purged after a day idle); the
/// session token is stored only as an HMAC (`anonymous_sessions`, purged with
/// conversation data after 30 days); question and answer text are never
/// stored (DEC-14).
abstract final class PolicyPages {
  static const privacy = PolicyPage(
    title: 'Privacy policy',
    updated: 'Last updated: 26 November 2026',
    intro:
        'Pitchy is a weather and safety app for football matches, made as a student research '
        'project. This page explains what information the app uses, where it goes, and how long '
        'it is kept.',
    sections: [
      PolicySection(
        'No accounts',
        paragraphs: [
          'Pitchy has no sign-up or login. It never asks for your name, email address or phone '
              'number.',
        ],
      ),
      PolicySection(
        'What stays on your device',
        bullets: [
          'Your settings: theme and colours, the role you picked in Ask Pitchy, and the match you '
              'set up (venue, kickoff time, age group, pitch surface).',
          'A saved copy of the last weather, alerts and safety assessment for your match, so the '
              'app can show it, labelled “not live”, when it can’t reach its server. Saved copies '
              'are deleted after 14 days, or when you set up a new match.',
          'Uninstalling the app removes all of this.',
        ],
      ),
      PolicySection(
        'What the app sends to the Pitchy server',
        bullets: [
          'The match you set up (venue, kickoff time, age group, optional pitch surface). Matches '
              'contain no personal information.',
          'In Ask Pitchy: your question and the role you picked. The app also gets an anonymous '
              'session code from the server. The app keeps it only in memory and never writes it to '
              'your device.',
          'Like any internet service, the server sees your device’s IP address when you connect. '
              'To limit how many requests one network can make, it keeps only a scrambled (hashed) '
              'form of it, never the address itself, and deletes that after a day without requests.',
        ],
      ),
      PolicySection(
        'What the Pitchy server keeps',
        bullets: [
          'Matches and their safety assessments: up to 135 days after kickoff, then deleted '
              'automatically.',
          'For each question asked in Ask Pitchy: the time, the role, the match, which AI service '
              'answered and whether it worked. Kept 30 days. The text of your question and of the '
              'answer is never stored, and these records can’t be linked back to you.',
          'For question limits: a scrambled (hashed) form of the session code and the times '
              'questions were asked. Deleted after 30 days without use.',
          'Weather data from the sources: 14 days.',
        ],
      ),
      PolicySection(
        'AI services',
        paragraphs: [
          'To write an answer, the server sends your question, the role, the match’s safety facts '
              'and passages from approved guidance documents to one of these AI services: Google '
              'Gemini, Groq or OpenRouter. It never sends your IP address, the session code or any '
              'other identifier. These services are used on free plans, whose terms may let them '
              'keep or review what they receive.',
          'Don’t type names or other personal details into Ask Pitchy.',
        ],
      ),
      PolicySection(
        'Weather sources',
        paragraphs: [
          'The Pitchy server, not your device, fetches weather from Open-Meteo, PAGASA and Vaisala '
              'Xweather, using the stadium’s location only.',
        ],
      ),
      PolicySection(
        'Other services',
        bullets: [
          'Check for updates asks GitHub (api.github.com) for the newest version. GitHub sees your '
              'IP address, as with any website.',
          'Send feedback and Contact support open GitHub Issues in your browser. Issues are public, '
              'and GitHub’s own privacy policy applies.',
          'Support development shows a Maya QR code. If you donate, you pay in Maya or '
              'your bank’s app, and their own privacy policies apply. Pitchy never sees your payment '
              'details and keeps no record of payments.',
          'The server runs on Microsoft Azure (Japan East), and its database on Supabase (Tokyo).',
        ],
      ),
      PolicySection(
        'Changes and contact',
        paragraphs: [
          'If this policy changes, the new version will be in the app and on the Pitchy website. '
              'For questions, use Contact support in Settings.',
        ],
      ),
    ],
  );

  static const disclaimer = PolicyPage(
    title: 'Safety disclaimer',
    updated: 'Last updated: 26 November 2026',
    intro:
        'Pitchy helps people make weather-safety decisions for football matches. It does not make '
        'those decisions.',
    sections: [
      PolicySection(
        'Officials decide.',
        paragraphs: [
          'The match officials and organisers named in your competition’s rules make every '
              'decision to play, pause, delay or stop a match. Pitchy shows information and what '
              'the approved rules say. It never says “stop play” or “safe to play”.',
        ],
      ),
      PolicySection(
        'No level is not “safe”.',
        paragraphs: [
          'When Pitchy shows no warning level, it means no rule was triggered by the data it has. '
              'It is not a statement that conditions are safe.',
        ],
      ),
      PolicySection(
        'Weather data can be late, missing or wrong.',
        paragraphs: [
          'Forecasts are uncertain. Every value shows its source and when it was checked; Pitchy '
              'labels old data “Stale” and missing data “Unavailable”, and never shows old data as '
              'current. When the app can’t reach its server, it shows a saved copy that is clearly '
              'marked “not live”.',
        ],
      ),
      PolicySection(
        'Lightning detection has limits.',
        paragraphs: [
          'Pitchy shows lightning detected by Vaisala Xweather near the stadium (within 40 km, in '
              'the past 5 minutes). Detection can miss strikes. The “about 10 km” level is Pitchy’s '
              'conversion of AFC’s 30-second rule, not AFC’s own wording.',
          'If you see lightning or hear thunder, follow your lightning procedure straight away, '
              'whatever the app shows.',
        ],
      ),
      PolicySection(
        'Official alerts are shown as issued.',
        paragraphs: [
          'PAGASA alerts are copied as published. Pitchy does not change or rate them. While '
              'PAGASA’s official data access is pending, Pitchy reads PAGASA’s public website, which '
              'can be unavailable.',
        ],
      ),
      PolicySection(
        'Ask Pitchy can be wrong.',
        paragraphs: [
          'Its answers are written by an AI from the safety facts and approved documents, and '
              'checked by Pitchy’s server, but they can still contain mistakes. They are '
              'explanations, not official decisions.',
        ],
      ),
      PolicySection(
        'In an emergency',
        paragraphs: [
          'Follow your venue’s emergency plan and call local emergency services. Don’t wait for the '
              'app.',
        ],
      ),
      PolicySection(
        'Research software',
        paragraphs: [
          'Pitchy is a student research project, provided as is, without any warranty.',
        ],
      ),
    ],
  );
}

/// Shows one [PolicyPage] as plain, readable text.
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.page});

  final PolicyPage page;

  static const _maxWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: PitchyTopBar(title: page.title),
      body: LayoutBuilder(
        builder: (context, c) {
          final side = ((c.maxWidth - _maxWidth) / 2).clamp(16.0, double.infinity);
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 20, side, 32),
            children: [
              Text(page.intro, style: text.bodyLarge),
              const SizedBox(height: 8),
              Text(page.updated, style: text.bodySmall),
              for (final s in page.sections) ...[
                const SizedBox(height: 24),
                Semantics(header: true, child: Text(s.heading, style: text.titleMedium)),
                const SizedBox(height: 8),
                for (final p in s.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(p, style: text.bodyLarge),
                  ),
                for (final b in s.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(child: Text('•  ', style: text.bodyLarge)),
                        Expanded(child: Text(b, style: text.bodyLarge)),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
