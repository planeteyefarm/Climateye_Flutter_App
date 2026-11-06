import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's selected map type preference across app launches.
/// Default is OpenStreetMap (OSM) (isSatellite = false).
class MapPreferences {
  MapPreferences._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'climateeye_is_satellite';

  /// Loads whether satellite view was selected. Defaults to false (OSM).
  static Future<bool> loadIsSatellite() async {
    try {
      final val = await _storage.read(key: _key);
      if (val == null) return false; // Default to OSM
      return val == 'true';
    } catch (_) {
      return false; // Fallback to OSM
    }
  }

  /// Saves the user's map view selection.
  static Future<void> saveIsSatellite(bool isSatellite) async {
    try {
      await _storage.write(key: _key, value: isSatellite.toString());
    } catch (_) {
      // Storage failure only affects persistence across cold starts.
    }
  }
}
