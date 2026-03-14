import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'p2p_service.dart';

/// Represents a point of interest (hospital, school, etc.)
class PointOfInterest {
  const PointOfInterest({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.icon,
    required this.color,
  });

  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final IconData icon;
  final Color color;

  LatLng get position => LatLng(latitude, longitude);
}

/// Static points of interest (hospitals, schools, etc.)
/// In a real app, these would be loaded from a database or API
const List<PointOfInterest> _pointsOfInterest = <PointOfInterest>[
  // Example locations - replace with real coordinates
  PointOfInterest(
    name: 'City Hospital',
    type: 'Hospital',
    latitude: 37.7749,
    longitude: -122.4194,
    icon: Icons.local_hospital,
    color: Colors.red,
  ),
  PointOfInterest(
    name: 'Central School',
    type: 'School',
    latitude: 37.7849,
    longitude: -122.4094,
    icon: Icons.school,
    color: Colors.blue,
  ),
  PointOfInterest(
    name: 'Emergency Warehouse',
    type: 'Storage',
    latitude: 37.7649,
    longitude: -122.4294,
    icon: Icons.warehouse,
    color: Colors.orange,
  ),
  PointOfInterest(
    name: 'Government Center',
    type: 'Government',
    latitude: 37.7549,
    longitude: -122.4394,
    icon: Icons.account_balance,
    color: Colors.green,
  ),
];

enum MapMode { tactical, warehouses }

enum NavigationTargetType { userId, warehouse, category }

class NavigationTarget {
  const NavigationTarget({
    required this.type,
    required this.query,
  });

  final NavigationTargetType type;
  final String query;
}

class OfflineMapScreen extends StatefulWidget {
  const OfflineMapScreen({
    super.key,
    required this.messages,
    required this.p2pService,
    this.initialMode = MapMode.tactical,
    this.initialNavigationTarget,
  });

  final List<P2PMessage> messages;
  final P2PService p2pService;
  final MapMode initialMode;
  final NavigationTarget? initialNavigationTarget;

  @override
  State<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends State<OfflineMapScreen> {
  late MapMode _mode;
  NavigationTarget? _navigationTarget;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _navigationTarget = widget.initialNavigationTarget;
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = _resolveCenter();

    return Scaffold(
      backgroundColor: Colors.black, // Forces AMOLED Dark Mode base
      appBar: AppBar(
        title: Text(
          _mode == MapMode.tactical ? 'TACTICAL RADAR' : 'WAREHOUSE MAP',
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0, // Removes shadow for cleaner look
        actions: <Widget>[
          IconButton(
            tooltip: 'Toggle map mode',
            icon: Icon(_mode == MapMode.tactical ? Icons.map : Icons.store),
            onPressed: () {
              setState(() {
                _mode = _mode == MapMode.tactical
                    ? MapMode.warehouses
                    : MapMode.tactical;
              });
            },
          ),
          IconButton(
            tooltip: 'Navigate to…',
            icon: const Icon(Icons.search),
            onPressed: _promptNavigation,
          ),
          IconButton(
            tooltip: 'Send SOS via sound',
            icon: const Icon(Icons.sos),
            onPressed: () {
              widget.p2pService.sendSoundMessage('HELP');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sent HELP signal via sound'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          if (widget.p2pService.isDeadReckoningActive)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.gps_off, color: Colors.orange, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'DEAD RECKONING',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
          // 0. Optional base tile layer for the warehouse map mode.
          if (_mode == MapMode.warehouses)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.offline_mesh',
            ),
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
          // 2. OVERLAY: Map markers derived from categorized messages, POIs, and user locations.
          MarkerLayer(
            markers: <Marker>[
              ..._buildMessageMarkers(center),
              ..._buildPOIMarkers(),
              ..._buildUserLocationMarkers(),
              ..._buildNavigationMarker(),
            ],
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMessageMarkers(LatLng center) {
    if (widget.messages.isEmpty) {
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

    for (final P2PMessage msg in widget.messages) {
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

  List<Marker> _buildPOIMarkers() {
    final List<PointOfInterest> pois = _mode == MapMode.warehouses
        ? _pointsOfInterest.where((PointOfInterest poi) => poi.type.toLowerCase() == 'storage').toList()
        : _pointsOfInterest;

    return pois.map((PointOfInterest poi) {
      return Marker(
        point: poi.position,
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Tooltip(
          message: '${poi.name} (${poi.type})',
          child: Container(
            decoration: BoxDecoration(
              color: poi.color.withOpacity(0.8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              poi.icon,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildUserLocationMarkers() {
    final Map<String, P2PMessage> lastMessagesByUser = <String, P2PMessage>{};

    // Find the most recent message with location for each user
    for (final P2PMessage msg in widget.messages) {
      if (msg.latitude != null && msg.longitude != null) {
        final String user = msg.sender;
        if (!lastMessagesByUser.containsKey(user) ||
            msg.timestamp.isAfter(lastMessagesByUser[user]!.timestamp)) {
          lastMessagesByUser[user] = msg;
        }
      }
    }

    return lastMessagesByUser.values.map((P2PMessage msg) {
      return Marker(
        point: LatLng(msg.latitude!, msg.longitude!),
        width: 35,
        height: 35,
        alignment: Alignment.center,
        child: Tooltip(
          message: 'Last location of ${msg.sender}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }).toList();
  }

  LatLng _resolveCenter() {
    final LatLng? target = _resolveNavigationTarget();
    if (target != null) {
      return target;
    }

    if (_mode == MapMode.warehouses) {
      final PointOfInterest warehouse = _pointsOfInterest.firstWhere(
        (PointOfInterest poi) => poi.type.toLowerCase() == 'storage',
        orElse: () => _pointsOfInterest.first,
      );
      return warehouse.position;
    }

    for (final P2PMessage msg in widget.messages.reversed) {
      if (msg.latitude != null && msg.longitude != null) {
        return LatLng(msg.latitude!, msg.longitude!);
      }
    }

    // Fallback to a sensible default if no messages have location yet.
    return const LatLng(37.7749, -122.4194);
  }

  LatLng? _resolveNavigationTarget() {
    if (_navigationTarget == null) return null;
    return _resolveTargetLocation(_navigationTarget!);
  }

  LatLng? _resolveTargetLocation(NavigationTarget target) {
    switch (target.type) {
      case NavigationTargetType.userId:
        final String id = target.query.trim();
        final List<P2PMessage> matches = widget.messages
            .where((P2PMessage m) => m.sender == id && m.latitude != null && m.longitude != null)
            .toList();
        if (matches.isNotEmpty) {
          final P2PMessage latest = matches.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
          return LatLng(latest.latitude!, latest.longitude!);
        }
        return null;

      case NavigationTargetType.warehouse:
        final String name = target.query.toLowerCase();
        final PointOfInterest poi = _pointsOfInterest.firstWhere(
          (PointOfInterest poi) =>
              poi.type.toLowerCase() == 'storage' && poi.name.toLowerCase().contains(name),
          orElse: () => _pointsOfInterest.firstWhere(
            (PointOfInterest poi) => poi.type.toLowerCase() == 'storage',
            orElse: () => _pointsOfInterest.first,
          ),
        );
        return poi.position;

      case NavigationTargetType.category:
        final String category = target.query.toLowerCase();
        final MessageCategory cat = _categoryFromString(category);
        final List<P2PMessage> messagesOfCategory = widget.messages
            .where((P2PMessage m) => m.category == cat && m.latitude != null && m.longitude != null)
            .toList();
        if (messagesOfCategory.isNotEmpty) {
          final P2PMessage latest = messagesOfCategory.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
          return LatLng(latest.latitude!, latest.longitude!);
        }
        return null;
    }
  }

  MessageCategory _categoryFromString(String value) {
    switch (value.toLowerCase()) {
      case 'medical':
        return MessageCategory.medical;
      case 'danger':
      case 'threat':
        return MessageCategory.danger;
      case 'resources':
      case 'logistics':
        return MessageCategory.resources;
      default:
        return MessageCategory.general;
    }
  }

  Future<void> _promptNavigation() async {
    NavigationTargetType selectedType = NavigationTargetType.userId;
    final TextEditingController controller = TextEditingController();

    final NavigationTarget? result = await showDialog<NavigationTarget>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setState) {
            return AlertDialog(
              title: const Text('Navigate to...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<NavigationTargetType>(
                    value: selectedType,
                    items: NavigationTargetType.values
                        .map((NavigationTargetType type) => DropdownMenuItem<NavigationTargetType>(
                              value: type,
                              child: Text(type.name.replaceAll('Id', ' ID').toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (NavigationTargetType? type) {
                      if (type != null) {
                        setState(() {
                          selectedType = type;
                        });
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Target type'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Value (ID / name / category)',
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final String query = controller.text.trim();
                    if (query.isEmpty) return;
                    Navigator.of(context).pop(NavigationTarget(
                      type: selectedType,
                      query: query,
                    ));
                  },
                  child: const Text('Go'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final LatLng? location = _resolveTargetLocation(result);
      setState(() {
        _navigationTarget = result;
      });

      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location not found for that target.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
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

  List<Marker> _buildNavigationMarker() {
    if (_navigationTarget == null) return <Marker>[];

    final LatLng? targetPosition = _resolveNavigationTarget();
    if (targetPosition == null) return <Marker>[];

    return <Marker>[
      Marker(
        point: targetPosition,
        width: 52,
        height: 52,
        alignment: Alignment.center,
        child: Tooltip(
          message: 'Navigation target',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.yellow.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Icon(
              Icons.navigation,
              color: Colors.black,
              size: 24,
            ),
          ),
        ),
      ),
    ];
  }
}
