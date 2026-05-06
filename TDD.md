# Pulse — TDD Pipeline

**Goal: Mike doesn't click. The test suite catches the regression; the team
fixes it; he sees the report.**

This pipeline replaces "Mike hand-tests on the Pixel" with "tests run in CI
on every push and on demand locally." When Mike reports a bug, the workflow
is: *write a failing test that pins the bug → fix the code → watch the test
go green → commit both together*. The next regression of the same surface
gets caught automatically.

## Test layers, in order of speed and coverage

| Layer            | Where           | What runs               | Runtime |
|------------------|-----------------|-------------------------|---------|
| Unit             | `test/`         | Pure-Dart logic         | < 1 s   |
| Widget           | `test/`         | Single-screen UI w/ fakes | 1–3 s |
| Integration smoke| `integration_test/` | Real device/emulator launch | ~60–90 s |

**The widget layer is where almost all bug coverage lives.** Widget tests
run on the Dart VM with no Android SDK, no Pixel, no emulator. They render
real Flutter widgets and can simulate taps, drags, long-presses, dialog
flows, scroll, etc. — everything Mike was clicking through manually.

## Run locally

```bash
# Fast host-side tests (unit + widget). Use this on every change.
flutter test

# Run a single bug's tests
flutter test test/routines_delete_test.dart

# Integration smoke against a connected Pixel (requires Android SDK + NDK
# + accepted licenses; Mac sets these up via Android Studio):
flutter test integration_test/smoke_test.dart -d 192.168.4.27:5555
```

> If `flutter test integration_test/...` errors with `LicenceNotAcceptedException`
> or `Unable to locate a Java Runtime`, the local Android toolchain isn't
> set up. Fix:
> ```bash
> export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
> sdkmanager --install "ndk;28.2.13676358"
> sdkmanager --licenses     # accept all
> ```
> CI does this automatically. Local-on-Pixel is the gold standard but is
> not required for day-to-day TDD — widget tests cover almost everything.

## Add a regression test for a new bug

When Mike reports `Bug X — clicking Foo does Bar instead of Baz`:

1. **Pick the right layer.**
   - Pure logic / decision function? → `test/<feature>_test.dart` as a unit test.
   - Single screen, a few interactions? → `test/<feature>_test.dart` as a `testWidgets`.
   - Cross-screen flow that depends on platform plugins (alarms, sqflite,
     real notifications)? → `integration_test/<feature>_test.dart`.

2. **Write the failing test FIRST.** Yes, before touching `lib/`. The test
   should fail with a message a future-you (or the next agent) can read
   and understand without rerunning Mike's manual repro:
   ```dart
   testWidgets('Bug X — long-press chip → Delete sheet → routine gone',
       (tester) async {
     final repo = FakeChecklistRepo();
     await repo.createRoutine('Workout');
     await tester.pumpWidget(MaterialApp(home: ChecklistPage(repo: repo)));
     await tester.pumpAndSettle();

     await tester.longPress(find.text('Workout'));
     await tester.pumpAndSettle();
     expect(find.text('Delete routine'), findsOneWidget);  // FAILS
     // ...
   });
   ```

3. **Run it. Watch it fail.** `flutter test test/<file>.dart`.
   The failure message is the spec.

4. **Fix the code.** Smallest change that turns the test green.

5. **Run the whole suite.** `flutter test` — make sure nothing else broke.

6. **Commit both** the test and the fix in one commit. Future Mike (or
   future agent) can `git log --grep="Bug X"` and see exactly what was
   broken, what was tested, and what was fixed.

### Template for new bug-test files

```dart
// Bug N — <one-line description that matches what Mike reported>.
//
// Repro: <how Mike triggered it>
// Diagnosis: <where the bug lives in lib/>
// Fix: <one-line summary of what changed>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/...';

void main() {
  group('Bug N — <surface>', () {
    testWidgets('<the precise expected behavior>', (tester) async {
      // arrange
      // act
      // assert
    });
  });
}
```

## How CI runs the suite

`.github/workflows/android.yml` defines three jobs:

1. **`test`** — `flutter analyze --no-fatal-infos` + `flutter test`. Runs
   on every push and PR. Fast, gates the rest.
2. **`integration_test`** — runs `flutter test integration_test/smoke_test.dart`
   on an Android emulator (`reactivecircus/android-emulator-runner@v2`,
   API 34, x86_64, google_apis). Catches plugin-channel / platform-init
   regressions that pure-Dart tests can't.
3. **`build`** — release APK, uploaded as the `pulse-release-apk` artifact.

If `test` fails, `integration_test` and `build` don't run. That's
deliberate — the cheap signal blocks the expensive jobs.

## What "Mike sees the result, not produces it" means in practice

Before this pipeline:
- Mike installs the APK on Pixel.
- Mike clicks through the routines list, tries to delete one, finds nothing happens, reports the bug.
- Claude writes a fix.
- Mike installs again, clicks again, verifies.

After this pipeline:
- Claude (or Mike) writes a failing widget test for the bug — that test
  *is* the click-through, in code.
- Claude fixes the underlying logic.
- The CI job runs the test. The PR shows ✅ next to "delete-routine
  regression test passes."
- Mike reads the PR and the green check. He doesn't click.

The bar for "fixed" is no longer "Mike re-clicked successfully" — it's
"the test that pins the bug is green and committed alongside the fix."

## Coverage map (current)

| Bug                                    | Test file                           | Status |
|----------------------------------------|-------------------------------------|--------|
| A — Cannot delete routines             | `test/routines_delete_test.dart`    | ✅ green |
| B — Notification action dispatch       | `test/alarm_handler_test.dart`      | ✅ green |
| C — Tap-to-action screen behavior      | `test/alarm_action_tap_test.dart`   | ✅ green (spec-pin; needs Mike) |
| D — Dee Stream card scroll             | `test/dee_card_scroll_test.dart`    | ✅ green |
| Smoke: app launches and renders home   | `integration_test/smoke_test.dart`  | runs in CI emulator |

## Known gaps (where Mike might still need to click)

- **Real Android system notification action buttons** (Bug B's true
  end-to-end surface). Pure Flutter integration tests can't tap an
  expanded notification's Snooze/Dismiss action buttons. The Dart
  dispatch logic is unit-tested via `decideNotificationAction`, but
  the round-trip from "OS fires notification → user taps action button →
  background isolate runs → alarm rescheduled" needs a UIAutomator-based
  Android instrumentation test, which is out of scope for v1 of this
  pipeline. **Bug B's existing repro path: schedule a Test alarm via
  Diagnostics → wait for notification → tap Snooze → verify the next
  alarm appears 5 minutes later.** Until the UIAutomator path is built,
  this remains a manual smoke after a release.
- **Real device hardware behaviors** — calendar permissions, network
  reachability to the relay, OS-level notification channels. Tested
  with the smoke integration_test on the CI emulator; on-device
  smoke is a release-time check.
- **Visual regressions** — colors, spacing, typography. Not currently
  covered. If a screen needs pixel-stable visuals, golden tests
  (`matchesGoldenFile`) are the next layer to add.

## Open spec questions for Mike

- **Bug C — what's the intended behavior of "tap on alarm itself"?**
  Currently, the AlarmActionScreen (a full Scaffold with countdown +
  Snooze 5/10/15 + Dismiss) opens when the user taps the system
  notification body. That's the only "box" we found. The screen is
  not a dialog; it's a route. If Mike meant tapping a card in the
  home page's "Scheduled alarms" list — those tiles currently have no
  onTap handler. Need clarification on which surface he was looking at
  and what he expected to happen.

## Future upgrades

- **Self-hosted runner driving the wireless-adb Pixel** — replaces the
  emulator job with a real-device job, gives full integration coverage
  including Android system notification actions. Requires Mac to be on.
- **UIAutomator-based instrumentation test** — closes the Bug B end-to-end
  gap by driving the actual notification shade.
- **Visual regression / golden tests** — add once the v1.2 surface
  stabilizes.
