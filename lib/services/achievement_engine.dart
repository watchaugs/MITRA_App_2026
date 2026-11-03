import 'package:isar/isar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/achievement_models.dart';

class AchievementEngine {
  final Isar isar;
  const AchievementEngine(this.isar);

  /// Record that the student was active TODAY and update the daily streak.
  /// Called on every meaningful activity (AR view, quiz pass). Idempotent within
  /// a day: multiple activities on the same day don't inflate the streak.
  ///   • same day as last active → no change
  ///   • exactly the next day     → streak + 1
  ///   • a gap of 2+ days         → streak resets to 1
  ///   • first ever activity      → streak = 1
  Future<void> _touchStreak(StudentProfile profile) async {
    final now = DateTime.now();
    final todayYmd = now.year * 10000 + now.month * 100 + now.day;
    final last = profile.lastActiveYmd;
    if (last == todayYmd) return; // already counted today

    if (last == 0) {
      profile.currentStreakDays = 1;
    } else {
      // Was the last active day exactly yesterday?
      final lastDate =
          DateTime(last ~/ 10000, (last % 10000) ~/ 100, last % 100);
      final diffDays = DateTime(now.year, now.month, now.day)
          .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
          .inDays;
      if (diffDays == 1) {
        profile.currentStreakDays = profile.currentStreakDays + 1;
      } else if (diffDays > 1) {
        profile.currentStreakDays = 1; // streak broken → restart
      }
      // diffDays <= 0 shouldn't happen (clock skew) → leave unchanged.
    }
    profile.lastActiveYmd = todayYmd;
  }

  /// Call this when a student views an AR module for >60 seconds
  Future<void> recordArView(String topicId) async {
    await isar.writeTxn(() async {
      // ✨ FIX: Explicitly target the collection by type to avoid pluralization errors
      final topicCollection = isar.collection<TopicProgress>();

      var progress =
          await topicCollection.filter().topicIdEqualTo(topicId).findFirst() ??
              (TopicProgress()..topicId = topicId);

      if (progress.hasViewedAr) return; // Prevent XP spamming

      progress.hasViewedAr = true;
      progress.arXpEarned = 20; // Base + Observation XP allocation

      // ✨ FIX: Force strict integer math to avoid double-to-int assignment errors
      int xpGained = progress.arXpEarned.toInt();
      if (progress.hasPassedQuiz && !progress.synergyApplied) {
        xpGained +=
            (progress.arXpEarned.toInt() + progress.quizXpEarned.toInt());
        progress.synergyApplied = true;
      }

      await topicCollection.put(progress);
      await _updateGlobalXp(xpGained);
    });
  }

  /// Call this when a student finishes a quiz
  Future<void> recordQuizPass(String topicId,
      {required bool perfectScore}) async {
    await isar.writeTxn(() async {
      final topicCollection = isar.collection<TopicProgress>();

      var progress =
          await topicCollection.filter().topicIdEqualTo(topicId).findFirst() ??
              (TopicProgress()..topicId = topicId);

      if (progress.hasPassedQuiz && !perfectScore) return;

      int newQuizXp = perfectScore ? 50 : 30;
      int xpDifference = newQuizXp - progress.quizXpEarned.toInt();

      progress.hasPassedQuiz = true;
      progress.quizXpEarned = newQuizXp;

      // ✨ FIX: Enforce strict integer conversions during synergy evaluation
      int xpGained = xpDifference;
      if (progress.hasViewedAr && !progress.synergyApplied) {
        xpGained +=
            (progress.arXpEarned.toInt() + progress.quizXpEarned.toInt());
        progress.synergyApplied = true;
      }

      await topicCollection.put(progress);
      await _updateGlobalXp(xpGained);
    });
  }

  /// Internal helper to update overall XP points, update Tiers, and assign Badges
  Future<void> _updateGlobalXp(int xpDelta) async {
    final profileCollection = isar.collection<StudentProfile>();
    var profile =
        await profileCollection.where().findFirst() ?? StudentProfile();

    // Ensure totalXp calculations use clear integer types
    profile.totalXp = (profile.totalXp.toInt() + xpDelta);

    // XP and streak advance TOGETHER in the same transaction — one brain, never
    // out of sync. Any XP-earning activity counts as activity for the day.
    await _touchStreak(profile);

    if (profile.totalXp >= 10000) {
      profile.currentTier = 'Gyani';
      _addBadge(profile, 'gyani_diamond');
    } else if (profile.totalXp >= 5000) {
      profile.currentTier = 'Acharya';
      _addBadge(profile, 'acharya_gold');
    } else if (profile.totalXp >= 2000) {
      profile.currentTier = 'Vidwan';
      _addBadge(profile, 'vidwan_spark');
    } else if (profile.totalXp >= 500) {
      profile.currentTier = 'Anveshak';
      _addBadge(profile, 'anveshak_silver');
    } else {
      profile.currentTier = 'Jigyasu';
      _addBadge(profile, 'jigyasu_bronze');
    }

    await profileCollection.put(profile);
  }

  void _addBadge(StudentProfile profile, String badgeId) {
    var badges = List<String>.from(profile.unlockedBadges);
    if (!badges.contains(badgeId)) {
      badges.add(badgeId);
      profile.unlockedBadges = badges;
    }
  }

  // ── Cloud-sync export / merge ──────────────────────────────────────────────
  // Snapshot the global profile (XP / streak / tier / badges) for the cloud.
  Future<Map<String, dynamic>> exportProfile() async {
    final profile = await isar.collection<StudentProfile>().where().findFirst();
    if (profile == null) return {};
    return {
      'totalXp': profile.totalXp,
      'currentStreakDays': profile.currentStreakDays,
      'lastActiveYmd': profile.lastActiveYmd,
      'currentTier': profile.currentTier,
      'unlockedBadges': profile.unlockedBadges,
    };
  }

  // Merge a cloud profile snapshot into local, MAX-WINS: higher XP, higher
  // streak (with the more recent lastActiveYmd), union of badges. Tier is then
  // recomputed from the merged XP so it's always consistent.
  Future<void> mergeProfile(Map<String, dynamic> cloud) async {
    if (cloud.isEmpty) return;
    await isar.writeTxn(() async {
      final col = isar.collection<StudentProfile>();
      final profile = (await col.where().findFirst()) ?? StudentProfile();

      final cXp = (cloud['totalXp'] as num?)?.toInt() ?? 0;
      profile.totalXp = profile.totalXp > cXp ? profile.totalXp : cXp; // max

      final cStreak = (cloud['currentStreakDays'] as num?)?.toInt() ?? 0;
      final cYmd = (cloud['lastActiveYmd'] as num?)?.toInt() ?? 0;
      if (cStreak > profile.currentStreakDays) {
        profile.currentStreakDays = cStreak;
      }
      if (cYmd > profile.lastActiveYmd) profile.lastActiveYmd = cYmd;

      // Union of badges.
      final merged = <String>{...profile.unlockedBadges};
      for (final b in (cloud['unlockedBadges'] as List? ?? const [])) {
        if (b is String) merged.add(b);
      }
      profile.unlockedBadges = merged.toList();

      // Recompute tier from merged XP (keep it consistent with the ladder).
      final xp = profile.totalXp;
      profile.currentTier = xp >= 10000
          ? 'Gyani'
          : xp >= 5000
              ? 'Acharya'
              : xp >= 2000
                  ? 'Vidwan'
                  : xp >= 500
                      ? 'Anveshak'
                      : 'Jigyasu';

      await col.put(profile);
    });
  }
}

// ═══════════════════════════════════════════════════════
// ✨ GLOBAL RIVERPOD PROVIDER DEFINITION
// ═══════════════════════════════════════════════════════

// Core dependency injection provider for Isar (Ensure your local DB initialization hooks into this)
final isarProvider = Provider<Isar>((ref) {
  throw UnimplementedError(
      'Initialize Isar in main.dart and override this provider.');
});

// Resolves the 'Undefined name achievementEngineProvider' crash in your UI screens
final achievementEngineProvider = Provider<AchievementEngine>((ref) {
  final isar = ref.watch(isarProvider);
  return AchievementEngine(isar);
});

// ✨ Listens to the local database in real-time. If XP changes, the UI updates instantly!
final studentProfileProvider = StreamProvider<StudentProfile>((ref) {
  final isar = ref.watch(isarProvider);
  return isar
      .collection<StudentProfile>()
      .where()
      .watch(fireImmediately: true)
      .map((profiles) =>
          profiles.isNotEmpty ? profiles.first : StudentProfile());
});
