# SOMA Alarm — UI Design Proposals

*Compiled 2026-05-01 by Claude Opus 4.6 (CCc session). Context: Mike described the current UI as "serviceable but bland — black background with white print. The alarm notification is cooler."*

---

## Current State

The app uses Material 3 dark theme with `ColorScheme.fromSeed(seedColor: 0xFF7C4DFF)`. This produces a neutral dark surface with purple accents — visually functional but generic. The home screen is a linear `ListView` with two sections (events, alarms) using default `Card` and `ListTile` widgets. The alarm notification screen has the most personality: a countdown timer with colored containers and snooze/dismiss buttons.

The dev-mode `deepOrange` AppBar is the only visual break from the default scheme.

---

## V1 — Theatrical

**File:** `v1-theatrical.html`

**Concept:** Deep velvet, warm gold footlights, stage-curtain motif. Ties directly to the FrontRow production aesthetic and the SOMA documentary sensibility.

**Palette:**
- Background: `#1A0A1E` (deep velvet) → `#0D0510` (blackout)
- Accent: `#E8A838` warm gold (footlight), `#C4862A` dimmed gold
- Text: `#F5E6D3` warm ivory, not pure white
- Event emphasis: `#8B3A4A` deep rose for imminent items
- Dev mode: `#E85D2A` preserved as left-border banner, not full AppBar

**Typography:** Playfair Display (display/titles) + Raleway (body/UI). Playfair brings theatrical gravitas; Raleway is clean and readable.

**Layout:** Events get glassmorphic cards with a gold left-border accent that shifts to rose when imminent. Subtle stage-curtain gradients at screen edges. A "footlight bar" — a thin gold gradient line — separates events from alarms. The alarm notification screen has an animated spotlight sweep and a large countdown in a circular frame.

**Motion:** Spotlight breathing animation on the alarm screen. Card hover lifts with gold glow. Spring-based entry would translate well to Flutter's `AnimatedContainer`.

**What works:** Distinctive, warm, and immediately recognizable as "not just another dark app." The theatrical language gives SOMA a brand identity that extends to HUD, video, and future Sidekick surfaces.

**What's risky:** Could feel heavy or ornate on a 6" phone screen. Velvet-and-gold has to be done with restraint or it tips into "casino app."

**Implementation effort:** **M** — Custom color scheme, 2 Google Fonts, gradient backgrounds, one CSS animation translated to Flutter. No complex widgets; mostly `Container` decoration and `AnimatedContainer`. ~3-4 days.

---

## V2 — Ambient

**File:** `v2-ambient.html`

**Concept:** Sleep-app calm. Midnight blues, dawn pinks, breathing gradients. Inspired by Calm/Headspace/Endel design language — atmospheric and restful.

**Palette:**
- Background: `#0B0E1A` midnight → `#1A1F3A` twilight → `#2A1F4A` nebula
- Accent: `#E8A0B4` dawn pink, `#F0C4A8` dawn peach
- Text: `#C8D0E8` cool moonlight
- Imminent: `#D47070` warm red
- Gradients: multi-stop navy-to-purple aurora on alarm screen

**Typography:** Cormorant Garamond (display — thin, literary, elegant) + DM Sans (body — clean, modern). Cormorant at weight 300 gives a distinctive look that doesn't compete for attention.

**Layout:** Adds a time-of-day hero clock (large `7:18` centered) that grounds the user. Events use pill-shaped time badges (`42 min`, `9h 42m`) instead of secondary text. Alarms are rounded pills with small circular icons. The alarm screen has concentric pulsing rings and a slowly shifting aurora gradient.

**Motion:** 8-second breathing gradient cycle. Pulsing countdown rings on alarm screen. Aurora background animation. All slow, calming — appropriate for an app that fires at 7 AM.

**What works:** Genuinely beautiful. The dawn/night palette shifts would let the app feel different at 7 AM vs 10 PM. The large time display makes the app ADHD-friendly — one glance tells you the time without searching. Very Material 3 Expressive-compatible.

**What's risky:** Could feel too passive for an alarm app. The calm aesthetic might make it easy to dismiss notifications rather than acting on them. Pink-and-blue is a well-trodden palette that might not feel distinctly "SOMA."

**Implementation effort:** **M** — Similar to V1: custom color scheme, 2 Google Fonts, gradient backgrounds, animations. The aurora effect on the alarm screen is the most complex piece (animated gradient in Flutter via `TweenAnimationBuilder`). ~3-4 days.

---

## V3 — The Forge

**File:** `v3-mike-special.html`

**Concept:** Dark carbon, ember orange, bold type. The app as a forge — where ideas become actions. Channels Mike's convergent-execution energy: ADHD-aware but not soft. Mission control density meets editorial clarity.

**Palette:**
- Background: `#0A0A0C` near-black carbon
- Primary accent: `#FF6B35` ember orange
- Secondary: `#FFB347` molten amber
- System: `#4ECDC4` electric teal for status/health indicators
- Text: `#E8E4E0` warm steel (not cold white)
- Surface: `#1A1A1E` graphite, `#252528` graphite-light
- Danger: `#FF4444` clear red

**Typography:** Fraunces variable serif (display — bold, warm, optically sized) + Space Grotesk (body — geometric, technical). Fraunces at weight 900 is arresting; Space Grotesk is the best monospaced-feeling proportional font for data display.

**Layout:** A "Next Up" hero card with a glowing top border dominates the home screen — this is the ADHD-friendly "single most important thing." Below it, events are dense rows with time columns and colored pipe indicators (hot orange = imminent). Status chips at the top show system health at a glance (webhook, calendar, alarm count). Alarms use teal indicator dots. The alarm screen has the largest countdown: 72px digits with a colon in ember orange.

**Motion:** Forge-pulse glow animation (slow ember breathing). Expanding ring on alarm screen. Heat-shimmer on the hero card. All short-period, energetic — matches the "wake up and act" intent.

**What works:** Highest information density without clutter. The "Next Up" hero solves Mike's stated need ("single most important thing"). Status chips give fleet-health visibility (aligns with SOMA ops culture). The ember palette is warm, energetic, and distinctly SOMA — it wouldn't be confused with any other app. Teal-for-health, orange-for-action, red-for-dismiss creates a clear semantic color language that extends to any future SOMA surface.

**What's risky:** The high-contrast orange-on-dark could feel aggressive at 5 AM. The density is right for Mike but might not translate to other users (irrelevant for v1 per Q11).

**Implementation effort:** **S-M** — Simplest of the three to implement in Flutter. No glassmorphism, no multi-stop animated gradients. Mostly `Container` with `BoxDecoration`, standard `Row`/`Column` layouts, one simple animation. Custom color scheme + 2 Google Fonts. ~2-3 days.

---

## Comparison Matrix

| Dimension | V1 Theatrical | V2 Ambient | V3 Forge |
|---|---|---|---|
| Brand distinctiveness | High — unique theatrical identity | Medium — beautiful but familiar genre | High — unique forge/mission-control identity |
| ADHD-friendliness | Medium — ornate elements could distract | Medium — calm but passive | High — hero card forces focus on ONE thing |
| 5 AM wake-up vibe | Warm but rich | Perfect — dawn calm | Energetic — could be aggressive |
| SOMA brand fit | FrontRow/documentary aligned | Sleep/wellness aligned | Operations/convergence aligned |
| Extension to HUD/Sidekick | Good — theatrical language transfers | Good — ambient language transfers | Best — status chips, density, color semantics transfer directly |
| Flutter implementation | M (~3-4 days) | M (~3-4 days) | S-M (~2-3 days) |
| Dev-mode visibility | Gold-bordered banner | Orange left-border banner | Orange left-border banner |

---

## Recommendation

**V3 — The Forge**, with one modification: borrow V2's large time-of-day display for the home screen.

Rationale:

1. **It solves the stated problem.** Mike said "bland." V3 is the least bland — it has visual energy, strong brand identity, and information density that respects Mike's intelligence without overwhelming his attention.

2. **The "Next Up" hero card is the killer feature.** It directly implements Sidekick's N3 requirement: "What's the single most important thing you should focus on right now?" No other proposal makes this the structural center of the home screen.

3. **The color semantics extend.** Ember for action, teal for health, red for danger — this is a design system, not just a palette. It ports directly to the HUD (`cc hud-ask` tiles), future Sidekick GUI, and any SOMA dashboard.

4. **Fastest to implement.** Least gradient complexity, most standard Flutter layouts. The team can ship this in 2-3 days and iterate.

5. **It matches Mike's personality.** From CULTURE.md: "default to proceeding," "never block," "dispatch don't micromanage." V3's aesthetic is forward momentum, not contemplation. V2 is beautiful but it says "rest." V1 says "attend the performance." V3 says "the forge is hot — let's go."

The one borrow from V2: the large time display. At 7 AM, half-awake, a giant `7:18` is more useful than any amount of design language. Add it above the "Next Up" card and you get the best of both worlds.

---

*Mockup files: `v1-theatrical.html`, `v2-ambient.html`, `v3-mike-special.html` — open in any browser to preview.*
