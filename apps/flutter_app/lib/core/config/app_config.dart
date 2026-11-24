/// Build-time configuration. The app holds no secrets: only the backend base URL
/// and whether to run against mock data.
///
/// Set at build or run time, for example:
/// `flutter run --dart-define=PITCHY_API_BASE_URL=https://example.test --dart-define=PITCHY_USE_MOCKS=false`
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.useMocks});

  factory AppConfig.fromEnvironment() {
    const baseUrl = String.fromEnvironment('PITCHY_API_BASE_URL', defaultValue: defaultApiBaseUrl);
    // Mocks are the default until the frontend is integrated with the backend (F2).
    const useMocks = bool.fromEnvironment('PITCHY_USE_MOCKS', defaultValue: true);
    return AppConfig(apiBaseUrl: Uri.parse(baseUrl), useMocks: useMocks);
  }

  /// The deployed backend (Azure Container Apps, DEC-07). Not a secret.
  static const defaultApiBaseUrl =
      'https://pitchy-api.ashyriver-dff30339.japaneast.azurecontainerapps.io';

  /// Base URL without the `/api/v1` prefix; the client adds it.
  final Uri apiBaseUrl;
  final bool useMocks;
}
