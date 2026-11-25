// Receives screenshots from integration_test/qa_flow_test.dart when run with
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/qa_flow_test.dart -d <device>
// and writes them to QA_SHOT_DIR (default: build/qa_shots).

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Platform.environment['QA_SHOT_DIR'] ?? 'build/qa_shots';
    final file = File('$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
