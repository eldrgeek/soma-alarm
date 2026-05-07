// Smoke test — verifies the integration_test pipeline works end-to-end on the
// connected Pixel. Run with:
//   flutter test integration_test/smoke_test.dart -d 192.168.4.27:5555
//
// If this passes, the harness is wired up: subsequent bug-specific tests
// (routines_delete_test.dart, dee_stream_scroll_test.dart, etc.) can rely on it.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:sidekick/src/app.dart';
import 'package:sidekick/theme/theme_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Pulse launches and renders the home AppBar', (tester) async {
    final themeProvider = ThemeProvider();
    await themeProvider.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: const SomaAlarmApp(),
      ),
    );
    // pumpAndSettle has a default 10-min timeout but the test rig
    // typically settles in under a second — give it a bounded budget.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Pulse'), findsOneWidget);
    // Dee Stream icon is in the AppBar — its presence proves the home page rendered.
    expect(find.byTooltip('Dee Stream'), findsOneWidget);
    expect(find.byTooltip('Routines'), findsOneWidget);
  });
}
