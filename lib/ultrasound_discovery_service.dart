import 'dart:async';

import 'package:ggwave_flutter/ggwave_flutter.dart';

/// Near-ultrasound discovery: one device emits an inaudible (or high-frequency)
/// sound encoding its identity; another device's microphone decodes it so the app
/// knows which Bluetooth/Nearby endpoint to connect to.
///
/// Replaces the deprecated Google Nearby Messages API (AudioBytes) with a
/// data-over-sound approach so "when the other phone hears the sound, it instantly
/// knows exactly which Bluetooth device to connect to."
class UltrasoundDiscoveryService {
  UltrasoundDiscoveryService._();

  static final UltrasoundDiscoveryService _instance = UltrasoundDiscoveryService._();

  factory UltrasoundDiscoveryService() => _instance;

  GGWaveFlutter? _ggwave;
  bool _emitting = false;
  bool _listening = false;
  String _currentToken = '';
  void Function(String token)? _onTokenReceived;
  Timer? _emitTimer;

  static const String _prefix = 'MESH:';

  /// Token must be short for fast transmission (e.g. government ID or endpoint name).
  void startEmitting(String token) {
    if (_emitting && _currentToken == token) return;
    stopEmitting();
    _currentToken = token;
    _emitting = true;
    _initGgwave();
    _emitOnce();
  }

  void _initGgwave() {
    if (_ggwave != null) return;
    _ggwave = GGWaveFlutter(
      GGWaveFlutterCallbacks(
        onMessageReceived: _onDecoded,
        onPlaybackStart: () {},
        onPlaybackStop: () {},
        onPlaybackComplete: () => _scheduleNextEmitAfterDelay(),
        onCaptureStart: () {},
        onCaptureStop: () {},
      ),
    );
  }

  void _onDecoded(String message) {
    if (!message.startsWith(_prefix)) return;
    final String token = message.substring(_prefix.length).trim();
    if (token.isEmpty) return;
    _onTokenReceived?.call(token);
  }

  void _emitOnce() {
    if (!_emitting || _ggwave == null) return;
    final String payload = '$_prefix$_currentToken';
    _ggwave!.togglePlayback(payload);
  }

  void _scheduleNextEmitAfterDelay() {
    if (!_emitting || _ggwave == null) return;
    _emitTimer?.cancel();
    _emitTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!_emitting) return;
      _emitOnce();
    });
  }

  void stopEmitting() {
    _emitting = false;
    _emitTimer?.cancel();
    _emitTimer = null;
  }

  /// When a token is decoded from the microphone, this callback is called.
  /// The app should find the Nearby endpoint with that name and request connection.
  void startListening(void Function(String token) onTokenReceived) {
    if (_listening) return;
    _onTokenReceived = onTokenReceived;
    _listening = true;
    _initGgwave();
    _ggwave?.toggleCapture();
  }

  void stopListening() {
    if (!_listening) return;
    _listening = false;
    _onTokenReceived = null;
    _ggwave?.toggleCapture();
  }

  void stop() {
    stopEmitting();
    stopListening();
  }
}
