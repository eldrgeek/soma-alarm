import 'package:flutter/material.dart';

// Track C stub — r8 scaffold.
// Track C replaces this with smartwatch vitals + medical appointments.
// Track B wires this into the Health tab (or as a sub-tab alongside HealthScreen).
// appendHealthRecord() lives in personal_health_appender.dart.

class PersonalHealthScreen extends StatelessWidget {
  const PersonalHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Health')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.watch_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Track C — pending',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
