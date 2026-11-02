import 'package:isar/isar.dart';

part 'achievement_models.g.dart';

@Collection()
class StudentProfile {
  Id id = Isar.autoIncrement;

  int totalXp = 0;
  String currentTier = 'Jigyasu';
  List<String> unlockedBadges = const ['jigyasu_bronze'];

  // ── Streak (daily activity) ────────────────────────────────────────────────
  // currentStreakDays: consecutive days the student was active.
  // lastActiveYmd: the last active calendar day as an int yyyymmdd (e.g.
  // 20261102), so streak maths needs no DateTime parsing and is timezone-stable
  // enough for a daily streak. 0 means "never active yet".
  int currentStreakDays = 0;
  int lastActiveYmd = 0;
}

@Collection()
class TopicProgress {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String topicId;

  bool hasViewedAr = false;
  bool hasPassedQuiz = false;

  int arXpEarned = 0;
  int quizXpEarned = 0;
  bool synergyApplied = false;
}
