import 'package:shared_preferences/shared_preferences.dart';

const String _kGovernmentIdKey = 'government_id';

/// Persists and retrieves the user's government-declared ID (e.g. National ID).
Future<String?> getGovernmentId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kGovernmentIdKey);
}

Future<void> setGovernmentId(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kGovernmentIdKey, id.trim());
}
