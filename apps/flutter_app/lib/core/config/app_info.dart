import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version, read from the build (pubspec `version:`), so
/// About and Check for Updates always match the binary.
class AppInfo {
  const AppInfo({required this.version, required this.buildNumber});

  static Future<AppInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(version: info.version, buildNumber: info.buildNumber);
  }

  final String version;
  final String buildNumber;

  /// `1.0.0 (build 1)`
  String get label => buildNumber.isEmpty ? version : '$version (build $buildNumber)';
}
