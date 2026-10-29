import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Mirrors the website's AuthContext: a hard-coded client-side credential
/// check. This is NOT secure authentication — the credentials ship inside
/// the app binary. Replace with a backend auth endpoint when one exists.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _key = 'skyeye_';
  static const _username = 'admin';
  static const _password = 'planeteye@2025';

  final _storage = const FlutterSecureStorage();

  Future<bool> isAuthenticated() async {
    try {
      return await _storage.read(key: _key) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    if (username != _username || password != _password) return false;
    try {
      await _storage.write(key: _key, value: 'true');
    } catch (_) {
      // Session persistence failure only means the user logs in again next launch.
    }
    return true;
  }

  Future<void> logout() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
