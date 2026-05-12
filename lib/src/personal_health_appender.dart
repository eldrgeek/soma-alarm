// Track C stub — r8 scaffold.
// Track C replaces this with the real JSONL writer.
//
// Record shape (for reference — Track C owns the authoritative schema):
//   id      ph-<uuid>
//   ts      ISO8601 UTC
//   kind    vitals | sleep | activity | appointment | medication
//   source  garmin | apple_health | manual | google_calendar
//   data    kind-specific map
//
// To surface a health event as a Pulse reminder, call appendReminder()
// from reminders_appender.dart with category "appointment" or "health_alert".

// ignore: avoid_unused_parameters
Future<void> appendHealthRecord(Map<String, dynamic> record) async {
  // no-op until Track C lands
}
