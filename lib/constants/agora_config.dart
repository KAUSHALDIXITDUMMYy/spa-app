/// Agora project credentials (same as web `.env` server tokens).
/// Warning: shipping the primary certificate in a client app exposes it; prefer a token server for production.
class AgoraConfig {
  static const String appId = 'e6297ee5ac684df4a251b54829b2e3c6';
  static const String appCertificate = '7ecf63677fbc4deb86839fd24ae660b9';
  static const int tokenExpireSeconds = 60 * 60 * 8; // 8h, matches Next.js API default
}
