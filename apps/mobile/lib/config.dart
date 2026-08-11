/// Default API base for local development.
/// On a physical device, replace with your Mac's LAN IP (e.g. http://192.168.1.10:5080).
class AppConfig {
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:5080',
  );

  static String get hubUrl => '$apiBase/hubs/ride';
}
