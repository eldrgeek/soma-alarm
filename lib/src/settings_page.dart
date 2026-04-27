import 'package:flutter/material.dart';

import 'alarms.dart';
import 'background.dart';
import 'settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _webhookCtrl = TextEditingController();
  bool _webhookEnabled = true;
  bool _morningEnabled = true;
  TimeOfDayLite _morning = const TimeOfDayLite(7, 0);
  int _lead = 15;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await Settings.webhookUrl();
    final wEn = await Settings.webhookEnabled();
    final mEn = await Settings.morningEnabled();
    final mt = await Settings.morningTime();
    final lead = await Settings.leadMinutes();
    if (!mounted) return;
    setState(() {
      _webhookCtrl.text = url;
      _webhookEnabled = wEn;
      _morningEnabled = mEn;
      _morning = mt;
      _lead = lead;
    });
  }

  Future<void> _save() async {
    await Settings.setWebhookUrl(_webhookCtrl.text.trim());
    await Settings.setWebhookEnabled(_webhookEnabled);
    await Settings.setMorningEnabled(_morningEnabled);
    await Settings.setMorningTime(_morning.hour, _morning.minute);
    await Settings.setLeadMinutes(_lead);
    await runBackgroundPoll();
    if (_morningEnabled) {
      await AlarmService.instance
          .scheduleMorningAlarm(hour: _morning.hour, minute: _morning.minute);
    } else {
      await AlarmService.instance.cancelMorningAlarm();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Webhook', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _webhookCtrl,
            decoration: const InputDecoration(
              labelText: 'POST URL',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            title: const Text('Send alarm events'),
            value: _webhookEnabled,
            onChanged: (v) => setState(() => _webhookEnabled = v),
          ),
          const Divider(height: 32),
          Text('Calendar alarms',
              style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            title: const Text('Lead time before event'),
            subtitle: Text('$_lead minutes'),
            trailing: DropdownButton<int>(
              value: _lead,
              items: const [5, 10, 15, 20, 30, 60]
                  .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                  .toList(),
              onChanged: (v) => setState(() => _lead = v ?? 15),
            ),
          ),
          const Divider(height: 32),
          Text('Morning routine',
              style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Daily morning alarm'),
            value: _morningEnabled,
            onChanged: (v) => setState(() => _morningEnabled = v),
          ),
          ListTile(
            title: const Text('Time'),
            subtitle: Text(
                '${_morning.hour.toString().padLeft(2, '0')}:${_morning.minute.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime:
                    TimeOfDay(hour: _morning.hour, minute: _morning.minute),
              );
              if (picked != null) {
                setState(() =>
                    _morning = TimeOfDayLite(picked.hour, picked.minute));
              }
            },
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
