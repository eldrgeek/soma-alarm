// Hand-maintained per round. Bump when starting a new round.
// Convention: round number + 1-line title, then a longer description.

const int kRoundNumber = 9;
const String kRoundTitle = 'r9 — in-app OTA update flow';
const String kRoundDescription = '''
r9 — In-app OTA update flow. About page checks Tailscale OTA server on open,
shows "Update available" with one-tap install. VersionChip shows ⬆ badge when
update is ready. publish-ota.sh automates APK build → server publish.
Builds on r8 (reminders + personal health tabs).
''';
