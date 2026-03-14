import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:nearby_connections/nearby_connections.dart';
// import 'package:sensors_plus/sensors_plus.dart'; // Temporarily disabled due to network issues

import 'notification_service.dart';
import 'ultrasound_discovery_service.dart';

/// Rate limiter to prevent message flooding/spamming
class MessageRateLimiter {
  MessageRateLimiter({
    this.maxMessagesPerMinute = 10,
    this.maxMessagesPerHour = 50,
  });

  final int maxMessagesPerMinute;
  final int maxMessagesPerHour;

  final Map<String, List<DateTime>> _userMessageTimes = <String, List<DateTime>>{};

  /// Check if a user can send a message. Returns true if allowed, false if rate limited.
  bool canSendMessage(String userId) {
    final DateTime now = DateTime.now();
    final List<DateTime> times = _userMessageTimes[userId] ?? <DateTime>[];

    // Clean old entries (older than 1 hour)
    times.removeWhere((DateTime time) => now.difference(time).inHours >= 1);

    // Check minute limit
    final int messagesInLastMinute = times
        .where((DateTime time) => now.difference(time).inMinutes < 1)
        .length;

    if (messagesInLastMinute >= maxMessagesPerMinute) {
      return false;
    }

    // Check hour limit
    if (times.length >= maxMessagesPerHour) {
      return false;
    }

    return true;
  }

  /// Record that a user sent a message
  void recordMessage(String userId) {
    final DateTime now = DateTime.now();
    _userMessageTimes.putIfAbsent(userId, () => <DateTime>[]).add(now);
  }

  /// Get remaining messages allowed in current minute for a user
  int getRemainingMessagesInMinute(String userId) {
    final DateTime now = DateTime.now();
    final List<DateTime> times = _userMessageTimes[userId] ?? <DateTime>[];

    final int messagesInLastMinute = times
        .where((DateTime time) => now.difference(time).inMinutes < 1)
        .length;

    return max(maxMessagesPerMinute - messagesInLastMinute, 0);
  }

  /// Get time until next message is allowed (in seconds)
  int getTimeUntilNextAllowed(String userId) {
    final DateTime now = DateTime.now();
    final List<DateTime> times = _userMessageTimes[userId] ?? <DateTime>[];

    if (times.isEmpty) return 0;

    // Find the oldest message in the last minute
    final DateTime oneMinuteAgo = now.subtract(const Duration(minutes: 1));
    final List<DateTime> recentMessages = times
        .where((DateTime time) => time.isAfter(oneMinuteAgo))
        .toList();

    if (recentMessages.length < maxMessagesPerMinute) return 0;

    // Time until the oldest message expires
    final DateTime oldestRecent = recentMessages.reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);
    final Duration timeSinceOldest = now.difference(oldestRecent);
    final int secondsUntilNext = 60 - timeSinceOldest.inSeconds;

    return max(secondsUntilNext, 0);
  }
}

/// Verification system for emergency alerts to prevent fake alerts
class AlertVerificationSystem {
  AlertVerificationSystem();

  final Map<String, DateTime> _recentAlerts = <String, DateTime>{};
  static const Duration _alertCooldown = Duration(minutes: 5);

  /// Check if an alert from this user should be verified
  bool shouldVerifyAlert(String userId, String alertType) {
    final String key = '$userId:$alertType';
    final DateTime now = DateTime.now();

    if (_recentAlerts.containsKey(key)) {
      final DateTime lastAlert = _recentAlerts[key]!;
      if (now.difference(lastAlert) < _alertCooldown) {
        return true; // Recent alert, require verification
      }
    }

    return false; // No recent alert, allow without verification
  }

  /// Record that an alert was sent
  void recordAlert(String userId, String alertType) {
    final String key = '$userId:$alertType';
    _recentAlerts[key] = DateTime.now();
  }

  /// Verify an alert (this could be extended with more sophisticated verification)
  Future<bool> verifyAlert(String userId, String alertType, String message) async {
    // For now, just check if the message contains expected emergency keywords
    // This could be extended with user confirmation, biometric verification, etc.
    final String upperMessage = message.toUpperCase();
    final bool hasEmergencyKeywords = upperMessage.contains('SOS') ||
                                     upperMessage.contains('EMERGENCY') ||
                                     upperMessage.contains('HELP');

    if (!hasEmergencyKeywords) {
      return false; // Not a real emergency alert
    }

    // Additional verification could be added here:
    // - Check if user has sent similar alerts recently
    // - Require user confirmation
    // - Use device sensors to detect emergency situation
    // - Verify with trusted authorities

    return true;
  }
}

/// Dead reckoning system for positioning when GPS is unavailable
class DeadReckoningSystem {
  DeadReckoningSystem();

  LatLng? _lastKnownPosition;
  DateTime? _lastUpdateTime;
  // StreamSubscription<AccelerometerEvent>? _accelerometerSubscription; // Disabled

  static const double _earthRadius = 6371000; // meters
  static const double _metersPerDegreeLat = _earthRadius * pi / 180.0;

  /// Start dead reckoning from a known position
  void startFromPosition(LatLng position) {
    _lastKnownPosition = position;
    _lastUpdateTime = DateTime.now();
    // _accelerometerSubscription?.cancel(); // Disabled
    // _accelerometerSubscription = accelerometerEventStream().listen(_onAccelerometerEvent); // Disabled
  }

  /// Stop dead reckoning
  void stop() {
    // _accelerometerSubscription?.cancel(); // Disabled
    // _accelerometerSubscription = null; // Disabled
  }

  // void _onAccelerometerEvent(AccelerometerEvent event) { // Disabled
  //   if (_lastKnownPosition == null || _lastUpdateTime == null) return;

  //   final DateTime now = DateTime.now();
  //   final double dt = now.difference(_lastUpdateTime!).inMilliseconds / 1000.0;

  //   if (dt > 1.0) { // Update every second
  //     // Simple integration of acceleration to velocity
  //     // This is a basic implementation - real dead reckoning would be more sophisticated
  //     _velocityX += event.x * dt * 0.1; // Scale down for realism
  //     _velocityY += event.y * dt * 0.1;

  //     // Apply damping to prevent runaway
  //     _velocityX *= 0.95;
  //     _velocityY *= 0.95;

  //     // Update position
  //     final double deltaLat = (_velocityY * dt) / _metersPerDegreeLat;
  //     final double deltaLng = (_velocityX * dt) / (_metersPerDegreeLat * cos(_lastKnownPosition!.latitude * pi / 180.0));

  //     _lastKnownPosition = LatLng(
  //       _lastKnownPosition!.latitude + deltaLat,
  //       _lastKnownPosition!.longitude + deltaLng,
  //     );

  //     _lastUpdateTime = now;
  //   }
  // }

  /// Get current estimated position (simplified time-based estimation)
  LatLng? getCurrentPosition() {
    if (_lastKnownPosition == null || _lastUpdateTime == null) return null;

    // For now, return the last known position
    // In a real implementation, this would use accelerometer data or other sensors
    // to estimate movement since the last GPS fix
    return _lastKnownPosition;
  }

  /// Check if dead reckoning is active
  bool get isActive => _lastKnownPosition != null; // Simplified check
}

/// Exception thrown when message rate limit is exceeded
class RateLimitException implements Exception {
  RateLimitException(this.message, {required this.waitTimeSeconds});

  final String message;
  final int waitTimeSeconds;

  @override
  String toString() => message;
}

enum MessageCategory {
  general,
  medical,
  danger,
  resources,
  logistics,
}

class P2PMessage {
  P2PMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
    this.category = MessageCategory.general,
    this.latitude,
    this.longitude,
    this.messageId,
  });

  final String sender;
  final String text;
  final DateTime timestamp;
  final MessageCategory category;
  final double? latitude;
  final double? longitude;
  /// Stable id for sync/dedupe when relaying history to new peers.
  final String? messageId;
}

class P2PService {
  P2PService({required String governmentId})
      : userName = governmentId,
        _nearby = Nearby() {
    statusNotifier.value = 'Idle';
  }

  final Nearby _nearby;

  /// User identity: government-declared ID (e.g. National ID).
  final String userName;

  /// Rate limiter to prevent message flooding
  final MessageRateLimiter _rateLimiter = MessageRateLimiter();

  /// Alert verification system to prevent fake emergency alerts
  final AlertVerificationSystem _alertVerifier = AlertVerificationSystem();

  /// Dead reckoning system for GPS-denied environments
  final DeadReckoningSystem _deadReckoning = DeadReckoningSystem();

  /// List of currently connected endpoint IDs.
  final List<String> _connectedEndpointIds = <String>[];

  /// Endpoints we've discovered; used to request connection (mesh: connect to all).
  final Set<String> _discoveredEndpointIds = <String>{};

  /// Avoid requesting connection to the same endpoint repeatedly.
  final Set<String> _pendingConnectionIds = <String>{};

  final Set<String> _seenMessageIds = <String>{};

  /// Check if dead reckoning is active (GPS-denied positioning)
  bool get isDeadReckoningActive => _deadReckoning.isActive;

  /// Maps endpointId -> human readable endpoint name.
  final Map<String, String> _endpointNames = <String, String>{};

  /// Notifies listeners of all received messages.
  final ValueNotifier<List<P2PMessage>> messagesNotifier =
      ValueNotifier<List<P2PMessage>>(<P2PMessage>[]);

  /// Notifies listeners of high-level mesh/network status.
  final ValueNotifier<String> statusNotifier =
      ValueNotifier<String>('Initializing');

  Timer? _meshRetryTimer;
  bool _meshActive = false;

  /// Sound-based discovery helper.
  UltrasoundDiscoveryService? _ultrasoundService;
  bool _isSoundDiscoveryActive = false;

  /// Notifies when a sound message is received (e.g. "HELP").
  final ValueNotifier<String?> soundMessageNotifier = ValueNotifier<String?>(null);

  /// Start both advertising and discovery using P2P_CLUSTER (mesh: connect to all peers).
  Future<void> startMesh() async {
    statusNotifier.value = 'Starting mesh as $userName';

    try {
      _meshActive = true;
      await _startAdvertising();
      await _startDiscovery();

      _updateMeshStatus();

      _meshRetryTimer?.cancel();
      _meshRetryTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!_meshActive) return;
        for (final String id in _discoveredEndpointIds.toList()) {
          if (!_connectedEndpointIds.contains(id) &&
              !_pendingConnectionIds.contains(id)) {
            _requestConnectionToEndpoint(id);
          }
        }
      });
    } catch (e) {
      statusNotifier.value = 'Error starting mesh: $e';
    }
  }

  /// Start ultrasound-based discovery/connection.
  /// This is optional and can be triggered separately from mesh discovery.
  Future<void> startSoundDiscovery() async {
    if (_isSoundDiscoveryActive) return;

    _isSoundDiscoveryActive = true;
    statusNotifier.value = 'Starting sound discovery…';

    final UltrasoundDiscoveryService ultrasound = UltrasoundDiscoveryService();
    _ultrasoundService = ultrasound;

    ultrasound.startEmitting(userName);
    ultrasound.startListening((String token) {
      // Quick signal path for short alert messages.
      if (token.toUpperCase() == 'HELP') {
        soundMessageNotifier.value = 'HELP';
        return;
      }

      for (final MapEntry<String, String> e in _endpointNames.entries) {
        if (e.value == token) {
          _requestConnectionToEndpoint(e.key);
          break;
        }
      }
    });

    statusNotifier.value = 'Sound discovery active';
  }

  /// Stop sound discovery (if active)
  Future<void> stopSoundDiscovery() async {
    if (!_isSoundDiscoveryActive) return;
    _isSoundDiscoveryActive = false;
    _ultrasoundService?.stop();
    _ultrasoundService = null;
    statusNotifier.value = 'Sound discovery stopped';
  }

  /// Returns true if sound discovery is currently active.
  bool get isSoundDiscoveryActive => _isSoundDiscoveryActive;

  /// Sends a brief sound-based message (e.g. "HELP") to nearby devices.
  void sendSoundMessage(String message) {
    UltrasoundDiscoveryService().sendMessage(message);
  }

  Future<void> _startAdvertising() async {
    await _nearby.startAdvertising(
      userName,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: (String endpointId, ConnectionInfo info) {
        _handleConnectionInitiated(endpointId, info);
      },
      onConnectionResult: (String endpointId, Status status) {
        _handleConnectionResult(endpointId, status);
      },
      onDisconnected: (String endpointId) {
        _handleDisconnected(endpointId);
      },
    );
  }

  Future<void> _startDiscovery() async {
    await _nearby.startDiscovery(
      userName,
      Strategy.P2P_CLUSTER,
      onEndpointFound:
          (String endpointId, String endpointName, String serviceId) {
        _endpointNames[endpointId] = endpointName;
        _discoveredEndpointIds.add(endpointId);
        _requestConnectionToEndpoint(endpointId);
      },
      onEndpointLost: (String? endpointId) {
        if (endpointId == null) return;
        _discoveredEndpointIds.remove(endpointId);
        _pendingConnectionIds.remove(endpointId);
        _handleDisconnected(endpointId);
      },
    );
  }

  void _startUltrasoundDiscovery() {
    final UltrasoundDiscoveryService ultrasound = UltrasoundDiscoveryService();
    ultrasound.startEmitting(userName);
    ultrasound.startListening((String token) {
      if (token.toUpperCase() == 'HELP') {
        soundMessageNotifier.value = 'HELP';
        return;
      }

      for (final MapEntry<String, String> e in _endpointNames.entries) {
        if (e.value == token) {
          _requestConnectionToEndpoint(e.key);
          break;
        }
      }
    });
  }

  /// After a peer disconnects, restart discovery so we keep scanning for others (and for them if they return).
  Future<void> _restartDiscovery() async {
    if (!_meshActive) return;
    try {
      await _nearby.stopDiscovery();
      await _startDiscovery();
    } catch (_) {}
  }

  /// Request connection to one endpoint (mesh: connect to every discovered peer).
  /// Staggered to avoid overwhelming the Bluetooth stack when many devices appear.
  void _requestConnectionToEndpoint(String endpointId) {
    if (_connectedEndpointIds.contains(endpointId)) return;
    if (_pendingConnectionIds.contains(endpointId)) return;
    _pendingConnectionIds.add(endpointId);

    _nearby.requestConnection(
      userName,
      endpointId,
      onConnectionInitiated: (String id, ConnectionInfo connectionInfo) {
        _handleConnectionInitiated(id, connectionInfo);
      },
      onConnectionResult: (String id, Status status) {
        _pendingConnectionIds.remove(id);
        _handleConnectionResult(id, status);
      },
      onDisconnected: (String id) {
        _handleDisconnected(id);
      },
    );
  }

  void _handleConnectionInitiated(
    String endpointId,
    ConnectionInfo info,
  ) {
    _endpointNames[endpointId] = info.endpointName;
    statusNotifier.value = 'Connection initiated with ${info.endpointName}';

    // Auto-accept all incoming connections without prompts.
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved:
          (String id, Payload payload) async {
        final List<int>? bytes = payload.bytes;
        if (bytes == null) {
          return;
        }
        final Uint8List bytePayload = Uint8List.fromList(bytes);
        final String decodedPayload = utf8.decode(bytePayload);

        if (decodedPayload.startsWith('SYNC|')) {
          _applyHistorySync(decodedPayload.substring(5));
          return;
        }

        final List<String> parts = decodedPayload.split('|');
        if (parts.isEmpty) {
          return;
        }
        final String messageId = parts[0];
        String actualMessage;
        MessageCategory category = MessageCategory.general;
        double? latitude;
        double? longitude;

        if (parts.length > 4) {
          // New framed format: messageId|category|lat|lng|text...
          category = _categoryFromWire(parts[1]);
          latitude = double.tryParse(parts[2]);
          longitude = double.tryParse(parts[3]);
          actualMessage = parts.sublist(4).join('|');
        } else if (parts.length > 2) {
          // Intermediate format: messageId|category|text...
          category = _categoryFromWire(parts[1]);
          actualMessage = parts.sublist(2).join('|');
        } else if (parts.length == 2) {
          // Backwards-compatible: messageId|text
          actualMessage = parts[1];
        } else {
          // Fallback: whole payload as message body.
          actualMessage = decodedPayload;
        }

        if (_seenMessageIds.contains(messageId)) {
          return;
        }
        _seenMessageIds.add(messageId);

        if (actualMessage.toUpperCase().contains('SOS')) {
          await NotificationService().showEmergencyAlert(
            title: 'EMERGENCY ALERT',
            body: actualMessage,
          );
        }

        _forwardPayload(id, bytePayload);
        final String senderName = _endpointNames[id] ?? 'Unknown';
        final List<P2PMessage> updated =
            List<P2PMessage>.from(messagesNotifier.value)
              ..add(
                P2PMessage(
                  sender: senderName,
                  text: actualMessage,
                  timestamp: DateTime.now(),
                  category: category,
                  latitude: latitude,
                  longitude: longitude,
                  messageId: messageId,
                ),
              );
        messagesNotifier.value = updated;
      },
      onPayloadTransferUpdate:
          (String id, PayloadTransferUpdate update) {
        // Could be used for progress; keep simple for now.
      },
    );
  }

  void _handleConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      if (!_connectedEndpointIds.contains(endpointId)) {
        _connectedEndpointIds.add(endpointId);
      }
      _updateMeshStatus();
      _sendHistoryToPeer(endpointId);

      // Stop sound discovery once we have a connection
      if (_isSoundDiscoveryActive) {
        stopSoundDiscovery();
      }
    } else {
      _connectedEndpointIds.remove(endpointId);
      _updateMeshStatus();
    }
  }

  void _updateMeshStatus() {
    final int n = _connectedEndpointIds.length;
    if (n == 0) {
      statusNotifier.value = 'Mesh running • no peers yet';
    } else {
      final String names = _connectedEndpointIds
          .map((String id) => _endpointNames[id] ?? id)
          .join(', ');
      statusNotifier.value = 'Mesh running • $n peer${n == 1 ? '' : 's'}: $names';
    }
  }

  void _handleDisconnected(String endpointId) {
    _connectedEndpointIds.remove(endpointId);
    _updateMeshStatus();
    _restartDiscovery();
  }

  /// Broadcast a text message to all connected endpoints.
  Future<void> broadcastMessage(
    String message, {
    MessageCategory category = MessageCategory.general,
  }) async {
    await sendMessage(message, category: category);
  }

  /// Sends an SOS alert over the mesh so all connected peers ring and show notification.
  /// Call this when the user presses the SOS button; local siren is handled separately.
  Future<void> broadcastSOSAlert() async {
    final String message = 'SOS - Emergency alert from $userName';

    // Verify the alert to prevent fake alerts
    final bool isVerified = await _alertVerifier.verifyAlert(userName, 'sos', message);
    if (!isVerified) {
      throw Exception('Emergency alert verification failed. Please ensure this is a genuine emergency.');
    }

    // Check rate limiting for emergency alerts (more lenient than regular messages)
    if (!_rateLimiter.canSendMessage(userName)) {
      // For emergency alerts, allow one emergency per hour even if rate limited
      final List<DateTime> times = _rateLimiter._userMessageTimes[userName] ?? <DateTime>[];
      final DateTime oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final int emergencyAlertsInLastHour = times
          .where((DateTime time) => time.isAfter(oneHourAgo))
          .length;

      if (emergencyAlertsInLastHour >= 3) { // Allow max 3 emergency alerts per hour
        final int waitTime = _rateLimiter.getTimeUntilNextAllowed(userName);
        throw RateLimitException(
          'Emergency alert rate limit exceeded. Please wait $waitTime seconds.',
          waitTimeSeconds: waitTime,
        );
      }
    }

    final String messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final LatLng? position = _getCachedOrLastKnownPosition();

    final String framedMessage = position != null
        ? '$messageId|danger|${position.latitude}|${position.longitude}|$message'
        : '$messageId|danger|$message';

    final Uint8List bytes = Uint8List.fromList(utf8.encode(framedMessage));
    _seenMessageIds.add(messageId);

    // Record the alert
    _alertVerifier.recordAlert(userName, 'sos');
    _rateLimiter.recordMessage(userName);

    await Future.wait(
      _connectedEndpointIds.map((String id) async {
        try {
          await _nearby.sendBytesPayload(id, bytes);
        } catch (_) {}
      }),
    );

    final List<P2PMessage> updated =
        List<P2PMessage>.from(messagesNotifier.value)
          ..add(
            P2PMessage(
              sender: userName,
              text: message,
              timestamp: DateTime.now(),
              category: MessageCategory.danger,
              latitude: position?.latitude,
              longitude: position?.longitude,
              messageId: messageId,
            ),
          );
    messagesNotifier.value = updated;
  }

  LatLng? _cachedPosition;
  DateTime? _cachedPositionTime;
  static const Duration _positionCacheMaxAge = Duration(seconds: 30);

  LatLng? _getCachedOrLastKnownPosition() {
    if (_cachedPosition != null &&
        _cachedPositionTime != null &&
        DateTime.now().difference(_cachedPositionTime!) < _positionCacheMaxAge) {
      return _cachedPosition;
    }

    // Fall back to dead reckoning if GPS is unavailable
    if (_deadReckoning.isActive) {
      return _deadReckoning.getCurrentPosition();
    }

    return null;
  }

  Future<void> _refreshPositionCache() async {
    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _cachedPosition = LatLng(last.latitude, last.longitude);
        _cachedPositionTime = DateTime.now();
      }
    } catch (_) {}
  }

  Future<void> sendMessage(
    String message, {
    MessageCategory category = MessageCategory.general,
  }) async {
    if (message.trim().isEmpty) {
      return;
    }

    // Check rate limiting
    if (!_rateLimiter.canSendMessage(userName)) {
      final int waitTime = _rateLimiter.getTimeUntilNextAllowed(userName);
      throw RateLimitException(
        'Message rate limit exceeded. Please wait $waitTime seconds before sending another message.',
        waitTimeSeconds: waitTime,
      );
    }

    final String messageId = DateTime.now().millisecondsSinceEpoch.toString();
    LatLng? position = _getCachedOrLastKnownPosition();
    if (position == null) {
      position = await _tryGetCurrentLocation();
      if (position != null) {
        _cachedPosition = position;
        _cachedPositionTime = DateTime.now();
      }
    }
    _refreshPositionCache();

    final String framedMessage;
    if (position != null) {
      framedMessage =
          '$messageId|${_categoryToWire(category)}|${position.latitude}|${position.longitude}|$message';
    } else {
      framedMessage = '$messageId|${_categoryToWire(category)}|$message';
    }

    final Uint8List bytes = Uint8List.fromList(utf8.encode(framedMessage));
    _seenMessageIds.add(messageId);

    // Record the message for rate limiting
    _rateLimiter.recordMessage(userName);

    // Send to all connected peers in parallel so everyone gets the message at once (mesh, no delay).
    await Future.wait(
      _connectedEndpointIds.map((String id) async {
        try {
          await _nearby.sendBytesPayload(id, bytes);
        } catch (_) {
          // Ignore individual send errors; connection handlers will update state.
        }
      }),
    );

    // Also add the message locally as sent by us.
    final List<P2PMessage> updated =
        List<P2PMessage>.from(messagesNotifier.value)
          ..add(
            P2PMessage(
              sender: userName,
              text: message,
              timestamp: DateTime.now(),
              category: category,
              latitude: position?.latitude,
              longitude: position?.longitude,
              messageId: messageId,
            ),
          );
    messagesNotifier.value = updated;

    // Trigger local emergency alert if this message contains SOS.
    if (message.toUpperCase().contains('SOS')) {
      await NotificationService().showEmergencyAlert(
        title: 'EMERGENCY ALERT',
        body: message,
      );
    }
  }

  void _forwardPayload(String originalSenderId, Uint8List bytes) {
    // Forward to all other peers in parallel (mesh: everyone gets it simultaneously).
    final List<String> others = _connectedEndpointIds
        .where((String id) => id != originalSenderId)
        .toList();
    for (final String id in others) {
      _nearby.sendBytesPayload(id, bytes).catchError((_) {});
    }
  }

  static const int _maxHistorySync = 100;

  /// Send our message history to a newly connected peer so they get all prior messages/alerts (e.g. B meets C and C gets what A had sent to B).
  void _sendHistoryToPeer(String endpointId) {
    final List<P2PMessage> list = messagesNotifier.value;
    if (list.isEmpty) return;

    final int start = list.length > _maxHistorySync ? list.length - _maxHistorySync : 0;
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (int i = start; i < list.length; i++) {
      final P2PMessage m = list[i];
      final String id = m.messageId ?? '${m.sender}_${m.timestamp.millisecondsSinceEpoch}';
      items.add(<String, dynamic>{
        'i': id,
        's': m.sender,
        't': m.text,
        'ts': m.timestamp.millisecondsSinceEpoch,
        'c': _categoryToWire(m.category),
        'la': m.latitude,
        'lo': m.longitude,
      });
    }
    final String jsonStr = jsonEncode(items);
    final String payload = 'SYNC|$jsonStr';
    final Uint8List bytes = Uint8List.fromList(utf8.encode(payload));
    _nearby.sendBytesPayload(endpointId, bytes).catchError((_) {});
  }

  void _applyHistorySync(String jsonStr) {
    try {
      final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
      final List<P2PMessage> toAdd = <P2PMessage>[];
      for (final dynamic e in list) {
        final Map<dynamic, dynamic> map = e as Map<dynamic, dynamic>;
        final String id = map['i'] as String? ?? '';
        if (id.isEmpty || _seenMessageIds.contains(id)) continue;
        _seenMessageIds.add(id);
        final String sender = map['s'] as String? ?? 'Unknown';
        final String text = map['t'] as String? ?? '';
        final int ts = map['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final MessageCategory category = _categoryFromWire(map['c'] as String? ?? 'general');
        final double? lat = (map['la'] as num?)?.toDouble();
        final double? lng = (map['lo'] as num?)?.toDouble();
        toAdd.add(P2PMessage(
          sender: sender,
          text: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
          category: category,
          latitude: lat,
          longitude: lng,
          messageId: id,
        ));
        if (text.toUpperCase().contains('SOS')) {
          NotificationService().showEmergencyAlert(
            title: 'EMERGENCY ALERT (synced)',
            body: text,
          );
        }
      }
      if (toAdd.isEmpty) return;
      final List<P2PMessage> updated = List<P2PMessage>.from(messagesNotifier.value)..addAll(toAdd);
      updated.sort((P2PMessage a, P2PMessage b) => a.timestamp.compareTo(b.timestamp));
      messagesNotifier.value = updated;
    } catch (_) {}
  }

  Future<void> stopMesh() async {
    try {
      _meshActive = false;
      _meshRetryTimer?.cancel();
      _meshRetryTimer = null;
      UltrasoundDiscoveryService().stop();
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
      _connectedEndpointIds.clear();
      _discoveredEndpointIds.clear();
      _pendingConnectionIds.clear();
      statusNotifier.value = 'Mesh stopped';
    } catch (e) {
      statusNotifier.value = 'Error stopping mesh: $e';
    }
  }

  void dispose() {
    _meshRetryTimer?.cancel();
    messagesNotifier.dispose();
    statusNotifier.dispose();
  }

  Future<LatLng?> _tryGetCurrentLocation() async {
    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final LatLng position = LatLng(last.latitude, last.longitude);
        // Start dead reckoning from this GPS position in case GPS is lost later
        if (!_deadReckoning.isActive) {
          _deadReckoning.startFromPosition(position);
        }
        return position;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final LatLng latLng = LatLng(position.latitude, position.longitude);
      // Start dead reckoning from this GPS position
      if (!_deadReckoning.isActive) {
        _deadReckoning.startFromPosition(latLng);
      }
      return latLng;
    } catch (_) {
      // GPS failed, try dead reckoning if available
      if (_deadReckoning.isActive) {
        return _deadReckoning.getCurrentPosition();
      }
      return null;
    }
  }

  MessageCategory _categoryFromWire(String value) {
    switch (value) {
      case 'medical':
        return MessageCategory.medical;
      case 'danger':
        return MessageCategory.danger;
      case 'resources':
        return MessageCategory.resources;
      case 'logistics':
        return MessageCategory.logistics;
      default:
        return MessageCategory.general;
    }
  }

  String _categoryToWire(MessageCategory category) {
    switch (category) {
      case MessageCategory.medical:
        return 'medical';
      case MessageCategory.danger:
        return 'danger';
      case MessageCategory.resources:
        return 'resources';
      case MessageCategory.logistics:
        return 'logistics';
      case MessageCategory.general:
      default:
        return 'general';
    }
  }

  /// Get remaining messages allowed in current minute
  int getRemainingMessagesInMinute() {
    return _rateLimiter.getRemainingMessagesInMinute(userName);
  }

  /// Get time until next message is allowed (in seconds)
  int getTimeUntilNextMessage() {
    return _rateLimiter.getTimeUntilNextAllowed(userName);
  }

  /// Check if user can send a message right now
  bool canSendMessage() {
    return _rateLimiter.canSendMessage(userName);
  }
}

