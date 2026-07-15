import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MetaGlassesStatus {
  final bool initialized;
  final String registration;
  final int deviceCount;
  final bool audioRouted;
  final bool mock;

  const MetaGlassesStatus({
    this.initialized = false,
    this.registration = 'UNINITIALIZED',
    this.deviceCount = 0,
    this.audioRouted = false,
    this.mock = false,
  });

  factory MetaGlassesStatus.fromMap(Map<dynamic, dynamic> value) =>
      MetaGlassesStatus(
        initialized: value['initialized'] == true,
        registration: value['registration']?.toString() ?? 'UNKNOWN',
        deviceCount: (value['deviceCount'] as num?)?.toInt() ?? 0,
        audioRouted: value['audioRouted'] == true,
        mock: value['mock'] == true,
      );
}

class MetaGlassesService {
  MetaGlassesService._();
  static final instance = MetaGlassesService._();

  static const _methods = MethodChannel('org.esr.sidekick/meta_glasses');
  static const _events = EventChannel('org.esr.sidekick/meta_glasses/events');

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<MetaGlassesStatus> get statuses {
    if (!supported) return const Stream.empty();
    return _events.receiveBroadcastStream().map(
          (event) => MetaGlassesStatus.fromMap(event as Map<dynamic, dynamic>),
        );
  }

  Future<MetaGlassesStatus> initialize() async {
    if (!supported) {
      return const MetaGlassesStatus(registration: 'PHONE SIMULATION');
    }
    final value =
        await _methods.invokeMapMethod<dynamic, dynamic>('initialize') ??
            const {};
    return MetaGlassesStatus.fromMap(value);
  }

  Future<void> register() async {
    if (supported) {
      await _methods.invokeMethod<void>('register');
    }
  }

  Future<Map<dynamic, dynamic>> routeAudio() async {
    if (!supported) return const {'routed': false, 'simulation': true};
    return await _methods.invokeMapMethod<dynamic, dynamic>('routeAudio') ??
        const {};
  }

  Future<void> clearAudioRoute() async {
    if (supported) {
      await _methods.invokeMethod<void>('clearAudioRoute');
    }
  }

  Future<MetaGlassesStatus> enableMock() async {
    if (!supported) {
      return const MetaGlassesStatus(
          registration: 'PHONE SIMULATION', mock: true);
    }
    final value =
        await _methods.invokeMapMethod<dynamic, dynamic>('enableMock') ??
            const {};
    return MetaGlassesStatus.fromMap(value);
  }

  Future<void> disableMock() async {
    if (supported) await _methods.invokeMethod<void>('disableMock');
  }
}
