import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const _kWebhookUrl = 'webhook_url';
  static const _kWebhookEnabled = 'webhook_enabled';
  static const _kMorningEnabled = 'morning_enabled';
  static const _kMorningHour = 'morning_hour';
  static const _kMorningMinute = 'morning_minute';
  static const _kEveningEnabled = 'evening_enabled';
  static const _kEveningHour = 'evening_hour';
  static const _kEveningMinute = 'evening_minute';
  static const _kLeadMinutes = 'lead_minutes';
  static const _kYeshieHost = 'yeshie_host';
  static const _kDraftBatch = 'draft_batch_v1';
  static const _kDispatchInputDraft = 'dispatch_input_draft';
  static const _kGitHubToken = 'github_token';
  static const _kGitHubRepos = 'github_repos';

  static const defaultWebhook =
      'https://vpsmikewolf.duckdns.org/soma/v1/alarm-event';

  // Web runs on the Mac itself → localhost. Mobile uses Tailscale to reach Mac.
  static const _defaultYeshieHostWeb = 'http://localhost:3333';
  static const _defaultYeshieHostMobile = 'http://100.72.65.118:3333';
  static String get defaultYeshieHost =>
      kIsWeb ? _defaultYeshieHostWeb : _defaultYeshieHostMobile;

  static Future<String> yeshieHost() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kYeshieHost) ?? defaultYeshieHost;
  }

  static Future<void> setYeshieHost(String host) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kYeshieHost, host);
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

  static Future<bool> eveningEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEveningEnabled) ?? true;
  }

  static Future<void> setEveningEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEveningEnabled, v);
  }

  static Future<TimeOfDayLite> eveningTime() async {
    final p = await SharedPreferences.getInstance();
    return TimeOfDayLite(
      p.getInt(_kEveningHour) ?? 21,
      p.getInt(_kEveningMinute) ?? 0,
    );
  }

  static Future<void> setEveningTime(int hour, int minute) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kEveningHour, hour);
    await p.setInt(_kEveningMinute, minute);
  }

  static Future<int> leadMinutes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLeadMinutes) ?? 15;
  }

  static Future<void> setLeadMinutes(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLeadMinutes, v);
  }

  // Draft batch: persisted as JSON-encoded list of strings.
  static const _defaultGitHubRepos = ['mikewolf/soma-alarm'];

  static Future<String?> githubToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kGitHubToken);
  }

  static Future<void> setGitHubToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGitHubToken, token);
  }

  static Future<List<String>> githubRepos() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kGitHubRepos);
    if (raw == null || raw.isEmpty) return _defaultGitHubRepos;
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return _defaultGitHubRepos;
    }
  }

  static Future<void> setGitHubRepos(List<String> repos) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGitHubRepos, jsonEncode(repos));
  }

  static Future<List<String>> draftBatch() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kDraftBatch);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDraftBatch(List<String> batch) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDraftBatch, jsonEncode(batch));
  }

  static Future<String> dispatchInputDraft() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDispatchInputDraft) ?? '';
  }

  static Future<void> saveDispatchInputDraft(String text) async {
    final p = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      await p.remove(_kDispatchInputDraft);
    } else {
      await p.setString(_kDispatchInputDraft, text);
    }
  }

  static String _kanbanReplyKey(String projectName) =>
      'kanban_reply_${projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  static Future<String> kanbanReplyDraft(String projectName) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kanbanReplyKey(projectName)) ?? '';
  }

  static Future<void> saveKanbanReplyDraft(String projectName, String text) async {
    final p = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      await p.remove(_kanbanReplyKey(projectName));
    } else {
      await p.setString(_kanbanReplyKey(projectName), text);
    }
  }
}

class TimeOfDayLite {
  final int hour;
  final int minute;
  const TimeOfDayLite(this.hour, this.minute);
}
