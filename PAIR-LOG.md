# Ward + Drew Pair Log — v3 Rebrand Session (2026-05-03)

This document records substantive disagreements between Ward (Flutter infrastructure) and Drew (design translation) during implementation.

---

## 1. Phase the work: ship v3 alone vs. all three themes at once

**[Ward]** We should ship the v3 Mike Special theme first and add the switcher in Phase 2. Mike said "low burden" but adding two extra theme objects plus provider plumbing and a settings picker is real engineering overhead that introduces scope creep on a build that's already complex.

**[Drew]** Pushback. Mike explicitly asked for the switcher from v0. The three ThemeData objects are structurally identical — 80% of the work is the same pattern repeated. If we do just one theme now, we pay the full infrastructure cost (ThemeProvider, ChangeNotifierProvider in main.dart, Consumer in app.dart) *plus* the cost of doing it again when we add the other two. The marginal cost of themes 2 and 3 after theme 1 is about 30 minutes each, not another infrastructure session.

**Resolution:** Drew's math held. All three themes built in parallel. Switcher included from v0. Total cost was exactly as estimated.

---

## 2. `google_fonts` runtime download vs. bundled font assets

**[Ward]** Runtime font download via `google_fonts` introduces a failure mode: fresh install without internet means no fonts. We should bundle the font files as assets in `pubspec.yaml` so the app works fully offline from first boot.

**[Drew]** The `google_fonts` package caches downloaded fonts in the app's document directory after first fetch. For Mike's daily-driver Pixel that will always have a network connection, the risk of a "first launch with no fonts" is near-zero. Bundling font files means checking ~500KB of binary assets into git, which pollutes diffs and makes the APK heavier for every future build.

**Resolution:** Ward accepted. `google_fonts` stays with runtime fetch + cache. Deferred to a maintenance task: if Mike ever needs offline-first guarantees, add font bundling then. Documented in release notes.

---

## 3. Settings style picker: radio tiles vs. visual card preview

**[Drew]** The style picker should show a mini visual preview of each theme — a small swatch strip with the primary + surface + text colors — so Mike can see what he's picking before applying it. Radio tiles with text subtitles are functional but don't convey the character of each style.

**[Ward]** A visual preview is a good future enhancement but adds a custom widget (color swatch row) that the user doesn't strictly need right now. The subtitles we wrote ("Carbon + ember — high density", "Midnight blues — calm") communicate the personality well enough. The switcher is live — selecting a radio button instantly updates the *entire app*, which is its own live preview.

**Resolution:** Ward's practicality won. Radio tiles implemented. The "live preview" behavior (instantaneous full-app repaint on selection) makes the missing static preview moot — you see the real result immediately. Drew noted this is actually a better UX than a static swatch.

---

## 4. `CardTheme` vs. flat surface color for gradient cards

**[Drew]** The v3 HTML mockup uses a `linear-gradient(135deg, graphite-light → graphite)` for the "next up" card and a 2px top-edge gradient bar (ember → molten → ember). We should implement these as custom card widgets with `DecoratedBox`, not rely on `CardThemeData.color` which only supports a flat color.

**[Ward]** Custom card widgets mean touching every `Card` widget in the existing codebase — home_page cards, alarm cards, settings tiles — none of which have gradient code. That's a lot of individual widget surgery for a visual nicety. The flat graphite-light color reads as "dark elevated surface" which captures the intent. The gradient bar is a purely decorative touch that the existing Card API can't do.

**Resolution:** Flat color now. Drew accepted the scope constraint. The `cardTheme: CardThemeData(color: graphiteLight)` approach keeps all existing Card widgets styled correctly with zero widget surgery. Drew documented the gradient bar as a follow-up enhancement: a `ForgeCard` wrapper widget that adds the top-edge gradient as a `Stack`/`DecoratedBox` decoration — any single card can opt into it later.

---

## 5. ThemeProvider load timing: splash frame vs. pre-runApp

**[Ward]** `ThemeProvider.load()` reads from `SharedPreferences`, which is `async`. If we `await` it before `runApp()`, there's a measurable delay (usually 20–50ms) before the first frame. On slow devices this could produce a brief white flash while the default MaterialApp renders before the theme loads. Better to show a default theme immediately and let the provider update asynchronously.

**[Drew]** A "white flash" in Mike Special's case is actually a *white* flash on a pitch-black app — very jarring. The SharedPreferences read is from local storage, not network; 20–50ms is negligible and happens during the `AlarmService.init()` await that's already in main(). We're not adding latency; we're batching it.

**Resolution:** Ward's objection was valid on slow devices but Drew's batching argument won for this specific case: `themeProvider.load()` is already running in parallel with `AlarmService.instance.init()` in the async main() chain. The theme is ready before `runApp()` fires. No observable flash. The pre-runApp `await` approach stays.

---

## 6. App package name: rename `soma_alarm` → `pulse`

**[Drew]** Full rebrand means renaming the Dart package from `soma_alarm` to `pulse` — this touches every `import` and the `name:` in pubspec.yaml but makes the codebase consistent with the new brand.

**[Ward]** Package rename at the Dart level is cosmetic and requires touching every import in every file. More importantly, the Android `applicationId` (`org.esr.soma_alarm`) can't be changed without treating it as a new app on the Play Store — the device will install it as a second app alongside the old one, losing all user data. Since Mike is sideloading via ADB (not Play Store), a rename would silently destroy his alarm history and SharedPreferences on next install.

**Resolution:** Ward prevailed on safety grounds. Dart package name stays `soma_alarm`; applicationId stays `org.esr.soma_alarm`. Only the user-visible label ("Pulse") and the Flutter `title` were changed.
