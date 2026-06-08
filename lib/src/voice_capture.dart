// Voice capture scaffold — gated behind kVoiceCaptureEnabled.
// TODO: set kVoiceCaptureEnabled = true once RECORD_AUDIO permission is
// confirmed in AndroidManifest.xml and speech_to_text integration is tested.
// Requires: pubspec speech_to_text: ^7.0.0 (already added).
// AndroidManifest additions needed before enabling:
//   <uses-permission android:name="android.permission.RECORD_AUDIO"/>
//   <uses-permission android:name="android.permission.INTERNET"/>

import 'package:flutter/material.dart';

const bool kVoiceCaptureEnabled = false;

// When kVoiceCaptureEnabled is true, replace this stub with a real
// SpeechToText-backed implementation that streams recognized words and
// appends each sentence as a checklist item via ChecklistRepo.addItem().
class VoiceCaptureButton extends StatelessWidget {
  final void Function(String line) onLine;

  const VoiceCaptureButton({super.key, required this.onLine});

  @override
  Widget build(BuildContext context) {
    // Stub: shows the button but presents a "not yet wired" snackbar.
    return FloatingActionButton.small(
      heroTag: 'voice_capture',
      tooltip: 'Voice capture (coming soon)',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice capture — wired in the morning.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: const Icon(Icons.mic_outlined),
    );
  }
}
