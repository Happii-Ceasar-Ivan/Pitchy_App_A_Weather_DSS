import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of files the app bundles itself to the open-source
/// licences page (Settings > Credits). Packages register their own; the
/// IBM Plex Mono font is a plain asset, so it needs this (the SIL Open Font
/// License asks that the licence travels with the font). Switzer is not open
/// source and is not listed here; it is credited on the Credits page.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/ibm_plex_mono/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['IBM Plex Mono font'], text);
  });
}
