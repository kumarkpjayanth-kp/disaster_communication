import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'p2p_service.dart';

class OfflineMapScreen extends StatelessWidget {
  const OfflineMapScreen({
    super.key,
    required this.messages,
  });

  final List<P2PMessage> messages;

  @override
  Widget build(BuildContext context) {
    final LatLng center = _resolveCenter();

    return Scaffold(
      backgroundColor: Colors.black, // Forces AMOLED Dark Mode base
      appBar: AppBar(
        title: const Text(
          'TACTICAL RADAR',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0, // Removes shadow for cleaner look
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 15,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: <Widget>[
          // 1. BASE LAYER: Polygon Grid (Drawn First, at the bottom)
          PolygonLayer(
            polygons: <Polygon>[
              Polygon(
                points: <LatLng>[
                  LatLng(center.latitude + 0.002, center.longitude - 0.002),
                  LatLng(center.latitude + 0.002, center.longitude + 0.002),
                  LatLng(center.latitude - 0.002, center.longitude + 0.002),
                  LatLng(center.latitude - 0.002, center.longitude - 0.002),
                ],
                borderColor: Colors.grey.shade700,
                borderStrokeWidth: 1.5,
                color: Colors.grey.withOpacity(0.12),
              ),
            ],
          ),
          // 2. OVERLAY: Map markers derived from categorized messages.
          MarkerLayer(
            markers: _buildMessageMarkers(center),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMessageMarkers(LatLng center) {
    if (messages.isEmpty) {
      return <Marker>[
        Marker(
          point: center,
          width: 50,
          height: 50,
          alignment: Alignment.center,
          child: const Icon(
            Icons.location_on,
            color: Colors.redAccent,
            size: 45,
          ),
        ),
      ];
    }

    final List<Marker> markers = <Marker>[];

    for (final P2PMessage msg in messages) {
      final LatLng point;
      if (msg.latitude != null && msg.longitude != null) {
        // Use the real GPS position when available.
        point = LatLng(msg.latitude!, msg.longitude!);
      } else {
        // Fallback: pin at the map center if no location was captured.
        point = center;
      }

      markers.add(
        Marker(
          point: point,
          width: 45,
          height: 45,
          alignment: Alignment.center,
          child: Tooltip(
            message: '${msg.sender}: ${msg.text}',
            child: Icon(
              _iconForCategory(msg.category),
              color: _colorForCategory(msg.category),
              size: 36,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  LatLng _resolveCenter() {
    for (final P2PMessage msg in messages) {
      if (msg.latitude != null && msg.longitude != null) {
        return LatLng(msg.latitude!, msg.longitude!);
      }
    }
    // Fallback to a sensible default if no messages have location yet.
    return const LatLng(37.7749, -122.4194);
  }

  IconData _iconForCategory(MessageCategory category) {
    switch (category) {
      case MessageCategory.medical:
        return Icons.local_hospital;
      case MessageCategory.danger:
        return Icons.warning;
      case MessageCategory.resources:
        return Icons.inventory_2;
      case MessageCategory.logistics:
        return Icons.route;
      case MessageCategory.general:
      default:
        return Icons.location_on;
    }
  }

  Color _colorForCategory(MessageCategory category) {
    switch (category) {
      case MessageCategory.medical:
        return Colors.redAccent;
      case MessageCategory.danger:
        return Colors.orangeAccent;
      case MessageCategory.resources:
        return Colors.lightGreenAccent;
      case MessageCategory.logistics:
        return Colors.cyanAccent;
      case MessageCategory.general:
      default:
        return Colors.blueAccent;
    }
  }
}