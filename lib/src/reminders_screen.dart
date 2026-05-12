import 'package:flutter/material.dart';

// Track A stub — r8 scaffold.
// Track A replaces this with the full Reminders tab (sr-02 through sr-11).
// Track B wires this widget into the bottom-nav shell.
// The stub must compile and show a non-blank placeholder so B can test nav.

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Track A — pending',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
