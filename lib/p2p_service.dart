import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:nearby_connections/nearby_connections.dart';

import 'notification_service.dart';
import 'ultrasound_discovery_service.dart';

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

  /// List of currently connected endpoint IDs.
  final List<String> _connectedEndpointIds = <String>[];

  /// Endpoints we've discovered; used to request connection (mesh: connect to all).
  final Set<String> _discoveredEndpointIds = <String>{};

  /// Avoid requesting connection to the same endpoint repeatedly.
  final Set<String> _pendingConnectionIds = <String>{};

  final Set<String> _seenMessageIds = <String>{};

  /// Read-only view of connected endpoint IDs.
  List<String> get connectedEndpointIds =>
      List<String>.unmodifiable(_connectedEndpointIds);

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

  /// Start both advertising and discovery using P2P_CLUSTER (mesh: connect to all peers).
  Future<void> startMesh() async {
    statusNotifier.value = 'Starting mesh as $userName';

    try {
      _meshActive = true;
      await _startAdvertising();
      await _startDiscovery();

      _startUltrasoundDiscovery();

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
    final String messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final LatLng? position = _getCachedOrLastKnownPosition();

    final String framedMessage = position != null
        ? '$messageId|danger|${position.latitude}|${position.longitude}|$message'
        : '$messageId|danger|$message';

    final Uint8List bytes = Uint8List.fromList(utf8.encode(framedMessage));
    _seenMessageIds.add(messageId);

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
      if (last != null) return LatLng(last.latitude, last.longitude);
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
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
}

