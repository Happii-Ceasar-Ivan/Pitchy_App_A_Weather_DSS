/// Fixed public addresses of the Pitchy project. Not secrets.
abstract final class ProjectLinks {
  /// The public GitHub repository (P-01: binaries on GitHub Releases).
  static const repo = 'https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS';

  /// Send feedback: a new public issue (user, 2026-11-26).
  static final feedback = Uri.parse('$repo/issues/new').replace(
    queryParameters: const {'title': 'Feedback: '},
  );

  /// Contact support: a new public issue (user, 2026-11-26).
  static final support = Uri.parse('$repo/issues/new').replace(
    queryParameters: const {'title': 'Help: '},
  );

  /// GitHub's API for the newest published release (P-08 update check).
  static final latestRelease = Uri.parse(
    'https://api.github.com/repos/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases/latest',
  );
}
