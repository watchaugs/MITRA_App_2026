// ═══════════════════════════════════════════════════════
// MITRA User Model — Mirrors MitraUser interface from
// store/useAuthStore.ts (Expo project)
// ═══════════════════════════════════════════════════════

class MitraUser {
  final String id;
  final String fullName;
  final String phone;
  final String role; // 'student' | 'teacher'
  final String? classGrade;
  final String? assignedState;
  final String? assignedDistrict;
  final String? languagePreference;
  final String? avatarEmoji;
  final int? totalXp;
  final int? currentStreakDays;
  final String? dashboardTheme;
  final String? lastLoginAt;
  final String? gender; // 'Male' | 'Female' | 'Other'
  final String? mobileBelongsTo; // 'Mother' | 'Father' | 'Self' | 'Other'

  const MitraUser({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    this.classGrade,
    this.assignedState,
    this.assignedDistrict,
    this.languagePreference,
    this.avatarEmoji,
    this.totalXp,
    this.currentStreakDays,
    this.dashboardTheme,
    this.lastLoginAt,
    this.gender,
    this.mobileBelongsTo,
  });

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';

  // 🛠️ Safely handles empty/blank names so the app shows a sensible fallback
  // instead of a blank name during the brief window before Firestore loads.
  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Student';
    final parts = trimmed.split(' ');
    final first = parts.first.trim();
    return first.isEmpty ? 'Student' : first;
  }

  factory MitraUser.fromJson(Map<String, dynamic> json) {
    return MitraUser(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'student',
      classGrade: json['class_grade'],
      assignedState: json['assigned_state'],
      assignedDistrict: json['assigned_district'],
      languagePreference: json['language_preference'],
      avatarEmoji: json['avatar_emoji'],
      totalXp: json['total_xp'] is int ? json['total_xp'] : null,
      currentStreakDays: json['current_streak_days'] is int
          ? json['current_streak_days']
          : null,
      dashboardTheme: json['dashboard_theme'],
      lastLoginAt: json['last_login_at'],
      gender: json['gender'],
      mobileBelongsTo: json['mobile_belongs_to'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'role': role,
        'class_grade': classGrade,
        'assigned_state': assignedState,
        'assigned_district': assignedDistrict,
        'language_preference': languagePreference,
        'avatar_emoji': avatarEmoji,
        'total_xp': totalXp,
        'current_streak_days': currentStreakDays,
        'dashboard_theme': dashboardTheme,
        'last_login_at': lastLoginAt,
        'gender': gender,
        'mobile_belongs_to': mobileBelongsTo,
      };

  // 🛠️ BUG-001 FIX: Added missing parameters to prevent data loss
  MitraUser copyWith({
    String? fullName,
    String? classGrade,
    String? assignedState,
    String? assignedDistrict,
    String? languagePreference,
    String? avatarEmoji,
    int? totalXp,
    int? currentStreakDays,
    String? dashboardTheme,
    String? lastLoginAt,
    String? gender,
    String? mobileBelongsTo,
  }) {
    return MitraUser(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone,
      role: role,
      classGrade: classGrade ?? this.classGrade,
      assignedState: assignedState ?? this.assignedState,
      assignedDistrict: assignedDistrict ?? this.assignedDistrict,
      languagePreference: languagePreference ?? this.languagePreference,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      totalXp: totalXp ?? this.totalXp,
      currentStreakDays: currentStreakDays ?? this.currentStreakDays,
      dashboardTheme: dashboardTheme ?? this.dashboardTheme,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      gender: gender ?? this.gender,
      mobileBelongsTo: mobileBelongsTo ?? this.mobileBelongsTo,
    );
  }
}
