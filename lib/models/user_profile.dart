import 'package:cloud_firestore/cloud_firestore.dart';

typedef UserRole = String;

class UserProfile {
  UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.createdAt,
    required this.isActive,
    this.displayName,
    this.allowChat = false,
    this.sessionId,
    this.lastLoginAt,
    this.isPending,
    this.termsAcceptedAt,
    this.zoomUserId,
    this.zoomUserEmail,
  });

  final String uid;
  final String email;
  final String role;
  final String? displayName;
  final DateTime createdAt;
  final bool isActive;
  final bool allowChat;
  final String? sessionId;
  final DateTime? lastLoginAt;
  final bool? isPending;
  final DateTime? termsAcceptedAt;
  final String? zoomUserId;
  final String? zoomUserEmail;

  static DateTime _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  static DateTime? _dateOpt(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      email: data['email'] as String? ?? '',
      role: (data['role'] as String? ?? 'subscriber').toLowerCase().trim(),
      displayName: data['displayName'] as String?,
      createdAt: _date(data['createdAt']),
      isActive: data['isActive'] as bool? ?? true,
      allowChat: data['allowChat'] == true,
      sessionId: data['sessionId'] as String?,
      lastLoginAt: _dateOpt(data['lastLoginAt']),
      isPending: data['isPending'] as bool?,
      termsAcceptedAt: _dateOpt(data['termsAcceptedAt']),
      zoomUserId: data['zoomUserId'] as String?,
      zoomUserEmail: data['zoomUserEmail'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'role': role,
        'displayName': displayName,
        'createdAt': Timestamp.fromDate(createdAt),
        'isActive': isActive,
        'allowChat': allowChat,
        if (sessionId != null) 'sessionId': sessionId,
        if (lastLoginAt != null) 'lastLoginAt': Timestamp.fromDate(lastLoginAt!),
        if (termsAcceptedAt != null) 'termsAcceptedAt': Timestamp.fromDate(termsAcceptedAt!),
      };
}
