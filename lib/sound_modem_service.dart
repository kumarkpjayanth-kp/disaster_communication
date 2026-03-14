import 'package:offline_mesh/notification_service.dart';

class SoundModemService {
  SoundModemService._internal();

  static final SoundModemService _instance = SoundModemService._internal();

  factory SoundModemService() => _instance;

  /// Triggers a loud emergency siren using the local notification channel.
  Future<void> broadcastAcousticSOS() async {
    await NotificationService().showEmergencyAlert(
      title: 'EMERGENCY SOS',
      body: 'Acoustic fallback siren activated.',
    );
  }

  Future<void> listenForAcousticSignatures() async {}
}
