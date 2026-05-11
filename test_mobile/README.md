# Pulse Mobile Screenshot Rig

Captures Pulse screenshots from real devices and the web app in mobile viewports,
then assembles them into a contact sheet for review at
`~/Projects/SOMA/audits/screenshots/mobile/contact-sheet.html`.

## Quick start

```bash
# Web viewport (fastest — requires web server at localhost:8088):
./scripts/mobile_screenshots.sh web

# Android — requires Pixel unlocked via PIN, USB connected:
./scripts/mobile_screenshots.sh android

# iOS — requires CocoaPods + device trusted or Simulator booted:
./scripts/mobile_screenshots.sh ios

# All platforms in sequence:
./scripts/mobile_screenshots.sh all

# Rebuild contact sheet from existing screenshots only:
./scripts/mobile_screenshots.sh contact-sheet
```

## Preconditions by platform

### Web (default, no build needed)
- Pulse web server running: `flutter run -d web-server --web-port=8088`
- Relay running: the Yeshie relay at `localhost:3333`
- Node.js + `playwright` npm package installed (already in `node_modules/`)

### Android (real device)
- Device unlocked — **PIN must be entered manually before running**
- USB debugging authorized (`adb devices` shows device as `device`, not `unauthorized`)
- App installed: `org.esr.sidekick` (check with `adb shell pm list packages | grep esr`)
- Missing: full Android SDK (`build-tools`, `platforms`) is needed for `flutter drive`
  - ADB screencap mode works without it (app already installed on device)
  - For `flutter drive` (integration test): install Android Studio or `sdkmanager`

### iOS (real device or simulator)
- **Blocked**: CocoaPods not installed. Fix: `gem install cocoapods`
- After CocoaPods: iOS Simulator runtimes are needed (`xcrun simctl list`)
  - If no runtimes: Xcode → Settings → Platforms → download iOS runtime
  - Or use real iPhone: trusted, trusted developer cert installed
- Run command: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screens.dart -d <ios-device-id>`

## Integration test (native mobile)

The `integration_test/screens.dart` test navigates the native mobile app
(the `!kIsWeb` path: `HomePage` → `SettingsPage` → `ChecklistPage` → Diagnostics dialog)
and takes a screenshot at each screen.

```bash
# Android
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screens.dart \
  -d 59080DLCQ0077G   # Pixel 10 Pro XL (unlock phone first)

# iOS (after CocoaPods setup)
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screens.dart \
  -d 00008030-001E399E2650802E   # real iPhone
```

Screenshots land in `build/test_screenshots/<platform>/` and are copied to
`~/Projects/SOMA/audits/screenshots/mobile/<platform>/` by the script.

## Adding a new screen

1. In `integration_test/screens.dart`, add a new `testWidgets` block or extend
   the existing `'Pulse mobile screenshot suite'` test.
2. Navigate to the screen (tap a button, push a route).
3. Call `await binding.takeScreenshot('NN-screen-name')`.
4. Run the driver command above and verify the new PNG appears in `build/test_screenshots/`.

## Contact sheet

The contact sheet at `~/Projects/SOMA/audits/screenshots/mobile/contact-sheet.html`
is self-contained (base64 images, no external deps). Open in any browser.

Regenerate after adding screenshots:
```bash
node scripts/build_contact_sheet.js ~/Projects/SOMA/audits/screenshots/mobile
```

## Infra blockers (as of 2026-05-09)

| Blocker | Fix | Owner |
|---------|-----|-------|
| CocoaPods not installed | `gem install cocoapods` | Mike |
| No iOS Simulator runtime | Xcode → Settings → Platforms → iOS | Mike |
| Pixel PIN-locked during ADB run | Unlock phone before running `./scripts/mobile_screenshots.sh android` | Mike |
| Android cmdline-tools missing | Install Android Studio or use `sdkmanager` | Mike |
| No macOS platform target | `flutter create --platforms=macos .` (then fix CocoaPods) | Optional |
