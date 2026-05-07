import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Save a screenshot to integration_test/screenshots/<bug>/<name>.png on the host
/// when running via `flutter test`. On-device runs (release mode) are no-ops.
///
/// Usage:
///   await captureScreenshot(binding, tester, bug: 'bug_a', name: 'passing');
Future<void> captureScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String bug,
  required String name,
}) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  // Real-device run: convertFlutterSurfaceToImage is required on Android.
  // Always try; the catch handles host-test runs and already-converted states.
  try {
    await binding.convertFlutterSurfaceToImage();
  } catch (_) {/* harmless if not on real device or already converted */}
  final bytes = await binding.takeScreenshot('$bug/$name');
  // When running on-host (`flutter test`) we can persist to disk directly.
  // When running on-device, takeScreenshot ships bytes back over the channel
  // and the test harness writes them — flutter_driver path. For the pipeline
  // we currently target (`flutter test integration_test/...`), bytes is a List<int>.
  try {
    final dir = Directory('integration_test/screenshots/$bug');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('integration_test/screenshots/$bug/$name.png');
    f.writeAsBytesSync(bytes);
  } catch (_) {
    // Best-effort: on-device runs may not have host filesystem access.
  }
}
