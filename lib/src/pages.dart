// Pulse's page registry.
//
// Every screen the bottom nav can show is declared here exactly once. Nav
// order, the About > Pages toggles, and programmatic navigation all read from
// this single list, so they cannot drift apart.
//
// Simplification (2026-07-29): Pulse shipped seven always-on tabs. Mike asked
// for a small default with everything else still reachable — so nothing was
// deleted. Every former tab is still registered below and one switch away in
// About; only [defaultEnabled] changed.
//
// STABLE IDS: an id is persisted in SharedPreferences. Renaming one silently
// drops that page out of a user's enabled set. Add a migration instead.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_screen.dart';
import 'conversation_screen.dart';
import 'health_screen.dart';
import 'jobs_screen.dart';
import 'kanban_screen.dart';
import 'on_device_chat_screen.dart';
import 'pulse_zero_screen.dart';
import 'reminders_screen.dart';
import 'today_screen.dart';

/// Shell hooks a page may need. Most pages ignore these; the Dee conversation
/// uses all three.
class PulsePageHost {
  const PulsePageHost({
    required this.isActive,
    required this.onRequestFocus,
    required this.searchTrigger,
  });

  /// True when this page is the one currently selected in the nav.
  final bool isActive;

  /// Ask the shell to switch to this page.
  final VoidCallback onRequestFocus;

  /// Toggled to pop a page's in-screen search affordance.
  final ValueNotifier<bool> searchTrigger;
}

typedef PulsePageBuilder = Widget Function(BuildContext, PulsePageHost);

class PulsePage {
  const PulsePage({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.blurb,
    required this.builder,
  });

  /// Stable, persisted identifier. See file header before renaming.
  final String id;

  /// Bottom-nav label.
  final String label;

  final IconData icon;
  final IconData selectedIcon;

  /// One line explaining the page, shown under its switch in About.
  final String blurb;

  final PulsePageBuilder builder;
}

class PulsePages {
  PulsePages._();

  // ── ids ───────────────────────────────────────────────────────────────────
  static const pulseZero = 'pulse_zero';
  static const gemma = 'gemma';
  static const dee = 'dee';
  static const today = 'today';
  static const jobs = 'jobs';
  static const activity = 'activity';
  static const reminders = 'reminders';
  static const health = 'health';
  static const board = 'board';

  /// Mike's requested default, in nav order.
  static const List<String> defaultEnabled = [pulseZero, gemma, dee];

  /// Registry order doubles as nav order — the default three lead.
  static final List<PulsePage> all = <PulsePage>[
    PulsePage(
      id: pulseZero,
      label: 'Pulse Zero',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      blurb: 'The live decision board — the same one at pulse-zero.netlify.app.',
      builder: (_, __) => const PulseZeroScreen(),
    ),
    PulsePage(
      id: gemma,
      label: 'Gemma',
      icon: Icons.offline_bolt_outlined,
      selectedIcon: Icons.offline_bolt,
      blurb: 'On-device AI. Works offline; can hand a thread to the team.',
      builder: (_, __) => const OnDeviceChatScreen(),
    ),
    PulsePage(
      id: dee,
      label: 'Dee',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      blurb: 'Conversation with Dee over the relay.',
      builder: (_, host) => ConversationScreen(
        isActive: host.isActive,
        onRequestFocus: host.onRequestFocus,
        searchTrigger: host.searchTrigger,
      ),
    ),
    PulsePage(
      id: today,
      label: 'Today',
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
      blurb: "Today's calendar events and alarms.",
      builder: (_, __) => const TodayScreen(),
    ),
    PulsePage(
      id: jobs,
      label: 'Jobs',
      icon: Icons.work_outline,
      selectedIcon: Icons.work,
      blurb: 'Dispatched jobs and their status.',
      builder: (_, __) => const JobsScreen(),
    ),
    PulsePage(
      id: activity,
      label: 'Activity',
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
      blurb: 'Daemon triage feed.',
      builder: (_, __) => const ActivityScreen(),
    ),
    PulsePage(
      id: reminders,
      label: 'Reminders',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      blurb: 'Reminders and deferred items.',
      builder: (_, __) => const RemindersScreen(),
    ),
    PulsePage(
      id: health,
      label: 'Health',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      blurb: 'Component status for the SOMA stack.',
      builder: (_, __) => const HealthScreen(),
    ),
    PulsePage(
      id: board,
      label: 'Board',
      icon: Icons.view_kanban_outlined,
      selectedIcon: Icons.view_kanban,
      blurb: 'Native project Kanban fed by the relay.',
      builder: (_, __) => const KanbanScreen(),
    ),
  ];

  static PulsePage? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Registry order, filtered to [ids]. Order of [ids] is deliberately ignored
  /// so the nav stays stable as pages are toggled on and off.
  static List<PulsePage> resolve(List<String> ids) =>
      all.where((p) => ids.contains(p.id)).toList(growable: false);
}

/// Persistence for the enabled-page set.
///
/// Lives here rather than in Settings so the registry stays self-contained —
/// Settings is imported by the very screens this file builds.
class PulsePagePrefs {
  PulsePagePrefs._();

  static const _key = 'enabled_pages_v1';

  /// Bumped whenever the enabled set changes, so the shell and About can
  /// rebuild without plumbing callbacks through the widget tree.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<List<String>> enabled() async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getStringList(_key);
    if (stored == null) return List<String>.from(PulsePages.defaultEnabled);

    // Drop ids from removed/renamed pages so a stale prefs entry can't leave
    // the shell with a page it cannot build.
    final known = stored.where((id) => PulsePages.byId(id) != null).toList();

    // Never leave the user with no pages at all — an empty nav is a dead app.
    if (known.isEmpty) return List<String>.from(PulsePages.defaultEnabled);
    return known;
  }

  static Future<void> setEnabled(List<String> ids) async {
    final p = await SharedPreferences.getInstance();
    final known = ids.where((id) => PulsePages.byId(id) != null).toList();
    if (known.isEmpty) return; // refuse to persist an empty nav
    await p.setStringList(_key, known);
    revision.value++;
  }

  /// Toggle one page. Returns false if the change was refused because it
  /// would have emptied the nav.
  static Future<bool> setPageEnabled(String id, bool on) async {
    final current = await enabled();
    if (on && current.contains(id)) return true;
    if (!on && !current.contains(id)) return true;

    final next = List<String>.from(current);
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
      if (next.isEmpty) return false;
    }
    await setEnabled(next);
    return true;
  }

  static Future<void> restoreDefaults() async =>
      setEnabled(List<String>.from(PulsePages.defaultEnabled));
}
