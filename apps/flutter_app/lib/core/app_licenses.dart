import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of files the app bundles itself to the open-source
/// licences page (Settings > Credits). Packages register their own; the
/// Roboto font is a plain asset, so it needs this (Apache License 2.0 asks
/// that the licence travels with the app).
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/roboto_license.txt');
    yield LicenseEntryWithLineBreaks(const ['Roboto font'], text);
  });
}
