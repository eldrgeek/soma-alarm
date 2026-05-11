import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Driver for the integration_test screenshot suite.
// Run with:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/screens.dart \
//     -d <device-id>
//
// Screenshots land in build/test_screenshots/<platform>/ by default,
// then the mobile_screenshots.sh script copies them to the SOMA audits dir.

Future<void> main() async {
  final platform = Platform.isAndroid
      ? 'android'
      : Platform.isIOS
          ? 'ios'
          : Platform.isMacOS
              ? 'macos'
              : 'unknown';

  final outDir = Directory('build/test_screenshots/$platform');
  await outDir.create(recursive: true);

  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('${outDir.path}/$name.png');
      await file.writeAsBytes(bytes);
      print('[screenshot] saved ${file.path}');
      return true;
    },
  );
}
