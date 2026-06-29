/// Backend API base URL — Next.js on the VPS (nginx :80 → :3000).
/// Override at build time: `flutter run --dart-define=API_BASE_URL=http://other-ip`
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://38.248.12.6',
  );
}
