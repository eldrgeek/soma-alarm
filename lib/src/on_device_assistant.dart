import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Availability state for the on-device GenAI feature (Gemini Nano via
/// ML Kit's Prompt API, backed by AICore).
///
/// Mirrors `com.google.mlkit.genai.common.FeatureStatus`
/// (UNAVAILABLE / DOWNLOADABLE / DOWNLOADING / AVAILABLE), plus an
/// [unsupported] bucket for platforms that can never run it (iOS, web,
/// desktop — this feature is Android-only).
enum AssistantAvailability {
  unsupported,
  unavailable,
  downloadable,
  downloading,
  available,
}

/// One event from the model-download progress stream.
class AssistantDownloadEvent {
  const AssistantDownloadEvent({required this.event, this.bytes, this.error});

  /// One of: `started`, `progress`, `completed`, `failed`.
  final String event;
  final int? bytes;
  final String? error;
}

/// Seam for on-device inference backends.
///
/// The chat UI ([OnDeviceChatScreen]) talks only to this interface. Swapping
/// the ML Kit GenAI Prompt API for a different on-device backend later
/// (flutter_gemma, a LiteRT-LM `.task` model, etc.) means writing a new
/// class that implements [OnDeviceAssistant] — no UI changes required.
abstract class OnDeviceAssistant {
  /// Whether the feature is usable right now, needs a model download first,
  /// or isn't available on this device/platform at all.
  Future<AssistantAvailability> checkAvailability();

  /// Downloads the on-device model. Emits progress events and completes the
  /// stream on success or failure. No-op stream if [checkAvailability]
  /// already reported [AssistantAvailability.available] or
  /// [AssistantAvailability.unsupported].
  Stream<AssistantDownloadEvent> downloadModel();

  /// Streams response text chunks for [prompt] as they're generated. The
  /// stream closes when generation finishes; failures surface as stream
  /// errors (never as an app crash — see implementations for the
  /// unavailable-device handling contract).
  Stream<String> ask(String prompt);

  /// Cancels any in-flight [ask] call.
  Future<void> cancel();

  /// Releases the native model handle. Safe to call repeatedly; a
  /// subsequent [ask] will recreate the handle on demand.
  Future<void> close();
}

/// [OnDeviceAssistant] backed directly by the ML Kit GenAI Prompt API
/// (`com.google.mlkit:genai-prompt`, Gemini Nano via AICore) through a
/// first-party platform channel — see
/// `android/app/src/main/kotlin/org/esr/sidekick/OnDeviceAssistantBridge.kt`
/// and `GenaiInferenceClient.kt`.
///
/// ### Why a hand-rolled platform channel instead of the
/// `google_mlkit_genai_prompt` pub.dev plugin
///
/// That plugin (0.2.0, the published version as of 2026-07-26) was the
/// preferred integration per spec, but its native Android implementation is
/// unusable for real inference today. Verified by reading
/// `android/src/main/kotlin/com/google_mlkit_genai_prompt/Prompt.kt` in the
/// `flutter-ml/google_ml_kit_flutter` repo (develop branch):
///
/// ```kotlin
/// private fun runInference(call: MethodCall, result: MethodChannel.Result) {
///     result.error("PromptError", "Prompt API inference not yet fully implemented", null)
/// }
/// // ...
/// RUN_INFERENCE_STREAMING -> { result.notImplemented() }
/// ```
///
/// `runInference` is a hardcoded stub that always errors, and
/// `runInferenceStreaming` isn't wired up at all (the Dart-side
/// `Prompt.runInferenceStreaming` is also just a stub with a comment
/// admitting it doesn't stream — "In a real implementation, this would use
/// an event channel to stream the results incrementally"). Only
/// `checkFeatureStatus` / `downloadFeature` are real on that plugin (via
/// reflection against the same underlying `com.google.mlkit.genai.prompt.*`
/// classes this file calls directly).
///
/// Since inference — the entire point of this feature — cannot work through
/// that plugin, we skip it and talk to the AICore-backed Kotlin API
/// ourselves, following the same platform-channel pattern already used in
/// this repo for `MetaGlassesBridge.kt` / `MetaGlassesService`. This also
/// gets us *real* token streaming, which the plugin doesn't have.
class MlKitGenaiAssistant implements OnDeviceAssistant {
  MlKitGenaiAssistant();

  static const MethodChannel _methods = MethodChannel(
    'org.esr.sidekick/on_device_assistant',
  );
  static const EventChannel _streamEvents = EventChannel(
    'org.esr.sidekick/on_device_assistant/stream',
  );
  static const EventChannel _downloadEvents = EventChannel(
    'org.esr.sidekick/on_device_assistant/download',
  );

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<AssistantAvailability> checkAvailability() async {
    if (!supported) return AssistantAvailability.unsupported;
    try {
      final status = await _methods.invokeMethod<int>('checkStatus');
      switch (status) {
        case 3:
          return AssistantAvailability.available;
        case 2:
          return AssistantAvailability.downloading;
        case 1:
          return AssistantAvailability.downloadable;
        default:
          return AssistantAvailability.unavailable;
      }
    } on MissingPluginException {
      // Platform channel not registered (shouldn't happen on Android, but
      // never crash the app over it).
      return AssistantAvailability.unsupported;
    } on PlatformException {
      // Any native-side failure (no AICore module, unsupported device,
      // missing Play services component) means "can't use it here", not a
      // crash.
      return AssistantAvailability.unavailable;
    }
  }

  @override
  Stream<AssistantDownloadEvent> downloadModel() {
    if (!supported) return const Stream.empty();
    final controller = StreamController<AssistantDownloadEvent>();
    late final StreamSubscription<dynamic> sub;
    sub = _downloadEvents.receiveBroadcastStream().listen(
      (event) {
        final map = Map<dynamic, dynamic>.from(event as Map);
        final e = AssistantDownloadEvent(
          event: map['event']?.toString() ?? 'progress',
          bytes: (map['bytes'] as num?)?.toInt(),
          error: map['error']?.toString(),
        );
        controller.add(e);
        if (e.event == 'completed' || e.event == 'failed') {
          sub.cancel();
          controller.close();
        }
      },
      onError: (Object e) {
        controller.addError(e);
        sub.cancel();
        controller.close();
      },
    );
    _methods.invokeMethod<void>('downloadModel').catchError((Object e) {
      if (!controller.isClosed) controller.addError(e);
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Stream<String> ask(String prompt) {
    if (!supported) {
      return Stream<String>.error(
        StateError('On-device AI is only available on Android.'),
      );
    }
    final controller = StreamController<String>();
    late final StreamSubscription<dynamic> sub;
    sub = _streamEvents.receiveBroadcastStream().listen(
      (event) {
        final map = Map<dynamic, dynamic>.from(event as Map);
        switch (map['event']) {
          case 'chunk':
            controller.add(map['text']?.toString() ?? '');
            break;
          case 'done':
            sub.cancel();
            controller.close();
            break;
          case 'error':
            controller.addError(
              Exception(map['error']?.toString() ?? 'Inference failed'),
            );
            sub.cancel();
            controller.close();
            break;
        }
      },
      onError: (Object e) {
        controller.addError(e);
        sub.cancel();
        controller.close();
      },
    );
    _methods.invokeMethod<void>('ask', {'text': prompt}).catchError((
      Object e,
    ) {
      if (!controller.isClosed) controller.addError(e);
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('cancelAsk');
    } on MissingPluginException {
      // ignore
    }
  }

  @override
  Future<void> close() async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('close');
    } on MissingPluginException {
      // ignore
    }
  }
}
