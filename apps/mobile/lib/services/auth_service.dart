import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  AuthService(this._api);

  final ApiClient _api;
  final _storage = const FlutterSecureStorage();

  AuthResponse? _session;
  UserProfile? profile;

  AuthResponse? get session => _session;
  bool get isAuthenticated => _session != null;
  String? get userId => _session?.userId;

  Future<void> restore() async {
    final token = await _storage.read(key: 'token');
    final userId = await _storage.read(key: 'userId');
    final email = await _storage.read(key: 'email');
    final name = await _storage.read(key: 'displayName');
    if (token != null && userId != null && email != null && name != null) {
      _session = AuthResponse(
        token: token,
        userId: userId,
        email: email,
        displayName: name,
      );
      _api.token = token;
      try {
        await loadProfile();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final data = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
    });
    await _persist(AuthResponse.fromJson(data as Map<String, dynamic>));
  }

  Future<void> register(String email, String password, String displayName) async {
    final data = await _api.post('/api/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    await _persist(AuthResponse.fromJson(data as Map<String, dynamic>));
  }

  Future<void> loadProfile() async {
    final data = await _api.get('/api/me');
    profile = UserProfile.fromJson(data as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> updateBike(BikeProfile bike) async {
    final data = await _api.put('/api/me/bike', bike.toJson());
    profile = UserProfile.fromJson(data as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> logout() async {
    _session = null;
    profile = null;
    _api.token = null;
    await _storage.deleteAll();
    notifyListeners();
  }

  Future<void> _persist(AuthResponse s) async {
    _session = s;
    _api.token = s.token;
    await _storage.write(key: 'token', value: s.token);
    await _storage.write(key: 'userId', value: s.userId);
    await _storage.write(key: 'email', value: s.email);
    await _storage.write(key: 'displayName', value: s.displayName);
    await loadProfile();
    notifyListeners();
  }
}
