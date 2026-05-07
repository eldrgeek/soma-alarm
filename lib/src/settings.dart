import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const _kWebhookUrl = 'webhook_url';
  static const _kWebhookEnabled = 'webhook_enabled';
  static const _kMorningEnabled = 'morning_enabled';
  static const _kMorningHour = 'morning_hour';
  static const _kMorningMinute = 'morning_minute';
  static const _kLeadMinutes = 'lead_minutes';
  static const _kRelayUrl = 'relay_url';
  static const _kDispatchToken = 'dispatch_token';

  static const defaultWebhook =
      'https://vpsmikewolf.duckdns.org/soma/v1/alarm-event';

  // Yeshie relay base URL (Dee Stream source). Configurable so Mike can
  // swap between Tailscale name and LAN IP without a rebuild. Default is
  // empty — the resolver tries kDefaultRelayCandidates instead, which
  // includes the Mac's known-good LAN IP. Setting an explicit value here
  // makes it the FIRST thing tried on each probe.
  static const defaultRelayUrl = '';

  static Future<String> relayUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRelayUrl) ?? defaultRelayUrl;
  }

  static Future<void> setRelayUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRelayUrl, url);
  }

  /// Shared-secret token for POST /dispatch_input. Mirrors the contents of
  /// ~/.dispatch/relay.secret on the relay host. Empty until Mike pastes it
  /// into Settings → Dispatch Token.
  static Future<String> dispatchToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDispatchToken) ?? '';
  }

  static Future<void> setDispatchToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDispatchToken, token.trim());
  }

  static Future<String> webhookUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kWebhookUrl) ?? defaultWebhook;
  }

  static Future<void> setWebhookUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWebhookUrl, url);
  }

  static Future<bool> webhookEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kWebhookEnabled) ?? true;
  }

  static Future<void> setWebhookEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWebhookEnabled, v);
  }

  static Future<bool> morningEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kMorningEnabled) ?? true;
  }

  static Future<void> setMorningEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMorningEnabled, v);
  }

  static Future<TimeOfDayLite> morningTime() async {
    final p = await SharedPreferences.getInstance();
    return TimeOfDayLite(
      p.getInt(_kMorningHour) ?? 7,
      p.getInt(_kMorningMinute) ?? 0,
    );
  }

  static Future<void> setMorningTime(int hour, int minute) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMorningHour, hour);
    await p.setInt(_kMorningMinute, minute);
  }

  static Future<int> leadMinutes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLeadMinutes) ?? 15;
  }

  static Future<void> setLeadMinutes(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLeadMinutes, v);
  }
}

class TimeOfDayLite {
  final int hour;
  final int minute;
  const TimeOfDayLite(this.hour, this.minute);
}
