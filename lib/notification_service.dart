import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();

  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the plugin only. Call this from main().
  /// Notification permission must be requested by the app (e.g. in StartupScreen)
  /// so that release APK shows the permission dialog with the others.
  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'disaster_alerts',
        'Disaster Alerts',
        description: 'Emergency disaster and SOS alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('siren'),
      );
      await androidPlugin.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  /// Show emergency alert with siren sound. Ensures init and permission before showing.
  Future<void> showEmergencyAlert({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();

    final PermissionStatus status = await Permission.notification.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.notification.request();
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'disaster_alerts',
      'Disaster Alerts',
      channelDescription: 'Emergency disaster and SOS alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('siren'),
      channelShowBadge: true,
      enableLights: true,
      ledColor: Color(0xFFE53935),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    final int id = Random().nextInt(100000).clamp(1, 0x7FFFFFFF);
    await _plugin.show(id, title, body, details);
  }
}