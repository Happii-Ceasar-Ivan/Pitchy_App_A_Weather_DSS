// Feedback and support go to the project's public GitHub Issues (user,
// 2026-11-26). Rows say where they lead and that issues are public.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/config/project_links.dart';
import 'package:pitchy/core/routing/app_router.dart';

import '../app_harness.dart';

void main() {
  test('links point at the public repository', () {
    expect(ProjectLinks.repo, 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS');
    expect(ProjectLinks.feedback.toString(), startsWith('${ProjectLinks.repo}/issues/new?'));
    expect(ProjectLinks.support.toString(), startsWith('${ProjectLinks.repo}/issues/new?'));
    expect(ProjectLinks.feedback.queryParameters['title'], 'Feedback: ');
    expect(ProjectLinks.support.queryParameters['title'], 'Help: ');
  });

  testWidgets('Send feedback and Contact support are on, and warn that issues are public', (
    tester,
  ) async {
    await pumpPitchyApp(tester, location: Routes.settings, size: const Size(390, 2400));
    for (final title in ['Send feedback', 'Contact support']) {
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isTrue, reason: title);
      expect(tile.onTap, isNotNull, reason: title);
    }
    expect(
      find.text('Opens GitHub Issues. Posts are public: leave out personal details.'),
      findsNWidgets(2),
    );
  });
}
