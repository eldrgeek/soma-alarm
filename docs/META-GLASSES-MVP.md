# Pulse + Meta Ray-Ban Glasses MVP

**Status:** implemented; physical APK build/pairing awaits one GitHub Packages credential and Mike's frames  
**Updated:** 2026-07-13  
**Authorship:** Mike Wolf (product direction and AI-team design), OpenAI Codex (Meta research, architecture, implementation, and verification pass)

## What this MVP does

Pulse is the Android companion runtime for Mike's Meta glasses. The frames supply the microphone and speakers through Android Bluetooth HFP; Meta's Wearables Device Access Toolkit (DAT) supplies app registration and live device state. A voice turn travels over Tailscale to Yeshie's Mac relay, which routes it to the existing SOMA team:

```text
Ray-Ban Meta mic/speakers
        ⇅ Bluetooth HFP
Pulse Android app (speech-to-text + text-to-speech + Meta DAT)
        ⇅ HTTP over Tailscale
Yeshie relay :3333
        ├─ conversation → CCDD → Dee / named SOMA persona
        ├─ Codex        → read-only ephemeral codex exec
        ├─ strategy     → Opie + Skip + Codex → Dee synthesis
        └─ dispatch     → Pulse dispatcher :3340 → cc-dispatch / Chat / Cowork
```

The Pulse tab has a headset button that opens **Meta Glasses**. That screen supports physical frames, DAT's mock device, phone-microphone use, and typed simulation.

## Supported voice grammar

- `Codex, assess the release plan.`
- `Ask Opie to challenge this strategy.`
- `Start a strategic discussion about Legends.`
- `Dispatch to code: fix the failing tests.`
- `Dispatch to cowork: draft the partner brief.`

The screen's Turn type and Teammate controls can be used instead of spoken routing. Explicit controls take precedence over inferred voice commands.

## One-time build setup

Meta publishes DAT through GitHub Packages. It requires a **personal access token (classic)** with `read:packages`; the Mac's normal `gh` OAuth token does not currently have that scope.

1. Create a classic token at GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic), selecting only `read:packages`.
2. Add this untracked line to `android/local.properties`:

   ```properties
   github_token=YOUR_CLASSIC_TOKEN
   ```

3. Build and install:

   ```bash
   flutter pub get
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

Never commit `local.properties` or the token.

## Connect Mike's glasses

1. Pair the frames normally with the Meta AI Android app and confirm calls/audio work.
2. In Meta AI, enable Developer Mode. DAT's developer-preview flow permits one developer-mode third-party app at a time.
3. Open Pulse → Pulse tab → headset button → **Connect**.
4. Approve Bluetooth and microphone permissions. If permissions were just requested, tap **Connect** again.
5. Complete Pulse registration in Meta AI, return to Pulse, and tap **Talk**.

The checked-in manifest uses developer-mode placeholder credentials (`0`). Before a non-developer release, replace these with the application ID and client token from the Meta Wearables Developer Center.

## Mock and desk testing

**Mock frames** exercises Meta DAT registration/device state without physical glasses. It does not synthesize the Bluetooth HFP microphone. Use **Test without glasses** or the phone microphone to validate the complete relay/team conversation flow.

Useful relay check:

```bash
curl -s http://localhost:3333/status
```

Typed turn example:

```bash
curl -s -X POST http://localhost:3333/pulse/voice/turn \
  -H 'Content-Type: application/json' \
  -d '{"text":"Codex, give me the next engineering move"}'
```

## Audio and preview limitations

- HFP is bidirectional 8 kHz mono. Android switches away from high-quality A2DP while the microphone is active, so spoken replies prioritize reliable turn-taking over music quality.
- Third-party code runs in Pulse on the paired phone, not on ordinary Ray-Ban Meta frames.
- DAT 0.8.0 is a developer preview. Registration requires current Meta AI and glasses firmware.
- A physical-frame acceptance pass is still required for Bluetooth routing, recognition accuracy, TTS volume, and a full registration cycle.

## Official references

- [Meta Wearables DAT Android repository and SDK setup](https://github.com/facebook/meta-wearables-dat-android)
- [Meta Wearables developer documentation](https://wearables.developer.meta.com/llms.txt?full=true)
- [DAT Android changelog](https://github.com/facebook/meta-wearables-dat-android/blob/main/CHANGELOG.md)
