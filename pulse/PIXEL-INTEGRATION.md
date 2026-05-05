# Pixel Integration Guide — What Mike Needs to Push

**Audience:** Mike Wolf (and future Ward when wiring this up)  
**Status:** Phase 0 — relay is live, FCM is stubbed

---

## What's Ready Now

1. **Relay endpoint** — `/pulse/cards` GET/POST/respond are live at `localhost:4243/pulse` (and on VPS at port 4243 when deployed).
2. **Sample cards** — JSON examples in `soma-alarm/pulse/cards/`. Post them to the relay to see the round-trip.
3. **Flutter widget scaffold** — `pulse_card_widget.dart` renders any card type from the data model.

## What Needs Doing Before the Pixel App Works

### Step 1: Add FCM to the Flutter project

```bash
# In ~/Projects/soma-alarm/
flutter pub add firebase_core firebase_messaging
```

Add to `pubspec.yaml`:
```yaml
firebase_core: ^3.0.0
firebase_messaging: ^15.0.0
```

Add `google-services.json` to `android/app/` (from Firebase console after creating project).

Add to `android/app/build.gradle`:
```groovy
apply plugin: 'com.google.gms.google-services'
```

Add to `android/build.gradle` dependencies:
```groovy
classpath 'com.google.gms:google-services:4.4.1'
```

### Step 2: Register FCM token with relay on app start

In `lib/main.dart`, after Firebase init:
```dart
final token = await FirebaseMessaging.instance.getToken();
if (token != null) {
  await http.post(
    Uri.parse('${Settings.webhookBaseUrl}/pulse/register'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'user_id': 'mike',
      'fcm_token': token,
      'device_id': 'pixel-7a-01',
      'device_auth_token': '<generated-once-at-install>',
    }),
  );
}
```

### Step 3: Handle incoming FCM messages

```dart
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  final cardId = message.data['pulse_card_id'];
  if (cardId != null) {
    // Fetch card from relay and show
    CardService.fetchAndShow(cardId);
  }
});

FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
```

### Step 4: Wire the card list to the relay

Add `PulseCardList` to the app home screen. On foreground resume, call:
```dart
GET /pulse/cards?limit=20
```
and render results with `PulseCardList`.

### Step 5: Post a test card

```bash
curl -X POST http://localhost:4243/pulse/cards \
  -H "Content-Type: application/json" \
  -H "X-Pulse-Signature: hmac-sha256=stub" \
  -d @soma-alarm/pulse/cards/card_yes_no_example.json
```

In development mode (`PULSE_ENV=development`), signature is not validated.

### Step 6: Enable exact-alarm permission (already in soma-alarm manifest)

No changes needed — `SCHEDULE_EXACT_ALARM` is already in AndroidManifest.xml.

---

## Environment Variables to Set on VPS

```
PULSE_HMAC_SECRET=<32-byte-random-hex>
PULSE_FCM_SERVER_KEY=<from-firebase-console>
PULSE_ENV=production
```

---

## Package Name Change Reminder

Before building the release APK for Pulse (vs. soma-alarm), change:
- `android/app/build.gradle`: `applicationId "com.soma.pulse"`
- `android/app/src/main/AndroidManifest.xml`: package + label
- `pubspec.yaml`: name → `soma_pulse`

See `RENAME-MIGRATION.md` for full checklist.
