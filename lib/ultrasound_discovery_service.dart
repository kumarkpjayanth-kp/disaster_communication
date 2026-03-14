import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Simplified sound-based discovery service using audio tones.
/// Replaces the complex ultrasound modulation with basic frequency-based signaling.
/// This is a simplified version that works with current Flutter packages.
class UltrasoundDiscoveryService {
  UltrasoundDiscoveryService._();

  static final UltrasoundDiscoveryService _instance = UltrasoundDiscoveryService._();

  factory UltrasoundDiscoveryService() => _instance;

  static final Set<void Function(String token)> _globalListeners = <void Function(String)>{};

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _emitting = false;
  bool _listening = false;
  String _currentToken = '';
  void Function(String token)? _onTokenReceived;
  Timer? _emitTimer;

  static const String _prefix = 'MESH:';
  static const int _discoveryFrequency = 2000; // 2kHz tone for discovery
  static const Duration _toneDuration = Duration(milliseconds: 500);
  static const Duration _pauseDuration = Duration(milliseconds: 1000);

  /// Token must be short for fast transmission (e.g. government ID or endpoint name).
  void startEmitting(String token) {
    if (_emitting && _currentToken == token) return;
    stopEmitting();
    _currentToken = token;
    _emitting = true;
    _emitDiscoveryTone();
  }

  /// Emit a simple audio tone for discovery
  Future<void> _emitDiscoveryTone() async {
    if (!_emitting) return;

    // Broadcast the token to any listening apps (simulated sound discovery).
    _broadcastToken(_currentToken);

    try {
      // Generate a simple tone using AudioPlayer
      // Note: In a real implementation, you might want to generate actual audio files
      // or use a more sophisticated audio generation approach.
      await _audioPlayer.setSource(AssetSource('discovery_tone.wav')); // Asset optional
      await _audioPlayer.resume();
    } catch (_) {
      // Playback not available; ignore.
    }

    // Schedule next emission
    _emitTimer = Timer(_toneDuration + _pauseDuration, _emitDiscoveryTone);
  }

  void stopEmitting() {
    _emitting = false;
    _emitTimer?.cancel();
    _audioPlayer.stop();
  }

  /// Send a short message over the sound channel.
  /// This is simulated by broadcasting to all listeners.
  void sendMessage(String message) {
    _broadcastToken(message);
  }

  void _broadcastToken(String token) {
    for (final void Function(String token) listener in _globalListeners) {
      try {
        listener(token);
      } catch (_) {
        // Ignore listener errors.
      }
    }
  }

  /// Start listening for discovery tones.
  void startListening(void Function(String token) onTokenReceived) {
    if (_listening) return;
    _listening = true;
    _onTokenReceived = onTokenReceived;
    _globalListeners.add(onTokenReceived);
  }

  void stopListening() {
    if (!_listening) return;
    _listening = false;
    if (_onTokenReceived != null) {
      _globalListeners.remove(_onTokenReceived);
    }
    _onTokenReceived = null;
  }

  /// Stop all discovery activities
  void stop() {
    stopEmitting();
    stopListening();
  }

  bool get isEmitting => _emitting;
  bool get isListening => _listening;
}
