# Pulse v0.1.0+2 — v3 Mike Special Rebrand

**Build date:** 2026-05-03  
**APK:** `build/app/outputs/flutter-apk/app-debug.apk` (147 MB debug)  
**Version code:** 2  
**Install command:** `adb install -r build/app/outputs/flutter-apk/app-debug.apk`

---

## What changed

### App renamed to Pulse
The app is now called **Pulse** everywhere — launcher icon label, app bar title, MaterialApp title, pubspec description. The Android package name (`org.esr.soma_alarm`) is unchanged to preserve ADB install history.

### Three visual styles, switchable in Settings
Open **Settings → Pulse style** to pick from:

| Style | Feel | Fonts |
|---|---|---|
| **Mike Special** *(default)* | Carbon black + ember orange. Dense, sharp, high-contrast. The Forge. | Fraunces (display) + Space Grotesk (body) |
| **Theatrical** | Velvet purple + warm gold. Rich, dramatic, serif-forward. | Playfair Display + Raleway |
| **Ambient** | Midnight blue + dawn pink. Calm, airy, breath-inspired. | Cormorant Garamond + DM Sans |

Style change is **live** — the app repaints immediately without a restart. The choice is persisted to `SharedPreferences` and survives restarts.

### Theme wired to all existing widgets
Every screen (home, settings, alarm action, diagnostics dialog, checklist) inherits the theme. Cards, buttons, toggles, radio buttons, snackbars, and dialogs all use the active palette. No hardcoded `Colors.deepPurple` or `Colors.red` left on the alarm countdown screen — those now use `colorScheme.primary` / `colorScheme.error`.

### Pulse card widget landed in `lib/src/`
`pulse_card_widget.dart` (the v0 scaffold for future Pulse card types) was moved from `pulse/` into `lib/src/` so it's part of the build. It's theme-aware — no hardcoded colors.

---

## What to test first on the phone

**Test the style switcher first.** Go to Settings, switch through all three styles, and confirm the entire UI repaints. Look at the alarm action screen — the countdown box color should match the active theme primary. This exercises the full `ThemeProvider → MaterialApp → all widgets` chain.

Then verify normal alarm flow (Settings → Diagnostics → Test Alarm → 30 seconds) still works correctly.

---

## Known gaps / deferred

- **Fonts need network on first run.** `google_fonts` downloads Space Grotesk, Fraunces, etc. from Google on first use; they cache after. On first install without internet the app falls back to system fonts.
- **APK is debug build.** No keystore for release signing is configured. Debug APK works for sideloading via ADB. Release signing is a one-time setup step when you want to push to Play Store.
- **Pulse card UI not yet wired to a live backend.** The widget exists and renders from JSON but `CardService.fetchCard()` is not implemented.
- **App icon not updated.** Still shows the default Flutter icon; a Pulse-branded icon is deferred.
- **No animated transitions between styles.** Style switch is instantaneous, not animated.

---

## Install / ADB notes

Once ADB sees the device (check with `adb devices`):

```bash
adb install -r /Users/mikewolf/Projects/soma-alarm/build/app/outputs/flutter-apk/app-debug.apk
```

The `-r` flag replaces the existing install and preserves app data (SharedPreferences, alarm DB).
