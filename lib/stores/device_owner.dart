// ═══════════════════════════════════════════════════════════════════════════
// One phone, many students.
//
// The phone keeps ONE live set of student progress: XP / rank / streak and
// per-lesson XP (Isar), quiz %, watched lessons, saved answers (mp_*), the
// fun kit (fun_*), and the student's consent + class-lock flags. Without this
// file, the next student to sign in on a shared phone inherited all of it,
// and the login merge then uploaded it into their cloud record.
//
// switchTo(uid) runs at sign-in, BEFORE anything shows or syncs:
//   • same student as last time → nothing to do
//   • first run after this update → the current data is claimed by this
//     student (the one already signed in on this phone)
//   • a different student → the previous student's set is saved to
//     progress_by_student/<their id>.json, the live set is cleared, and this
//     student's own saved set (if any) is loaded back. The cloud merge then
//     runs on the right student's data.
//
// Device settings (theme, app language, data saver, AR coach marks, sync
// timers, the dashboard's mastery %) are not per student and are left alone.
// Queued uploads are tagged per student already (quiz attempts, telemetry).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/achievement_models.dart';

class DeviceOwner {
  DeviceOwner._();

  static const _ownerKey = 'device_progress_owner';
  static const _maxSaved = 60; // saved students kept on one phone

  static Future<void> _chain = Future<void>.value();

  /// The student whose progress is live on this phone (null before the first
  /// sign-in after this update).
  static String? ownerOf(SharedPreferences prefs) => prefs.getString(_ownerKey);

  /// Waits for any switch in progress (call before reading or syncing).
  static Future<void> settled() => _chain;

  /// Set once this phone has merged [uid]'s cloud copy into the live set.
  /// Cleared whenever their set is (re)loaded, so nothing is uploaded until
  /// the cloud copy is merged in again (a fresh set must never overwrite it).
  static String mergedKey(String uid) => 'progress_merged_$uid';

  /// Per-student keys in SharedPreferences.
  static bool _isStudentKey(String k) =>
      (k.startsWith('mp_') && k != 'mp_mastery_pct') ||
      k.startsWith('fun_') ||
      k == 'consentGiven' ||
      k == 'consentDate' ||
      k == 'consentPendingGrant' ||
      k == 'consentWithdrawn' ||
      k == 'classLockedAt';

  /// Makes [uid]'s progress the live set. Runs one at a time. Returns true
  /// when the live data changed (screens reading prefs should refresh).
  static Future<bool> switchTo(String uid,
      {required SharedPreferences prefs, Isar? isar}) {
    final run = _chain.then((_) => _switch(uid, prefs, isar));
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<bool> _switch(
      String uid, SharedPreferences prefs, Isar? isar) async {
    if (uid.isEmpty) return false;
    final owner = prefs.getString(_ownerKey);
    if (owner == uid) return false;
    if (owner == null || owner.isEmpty) {
      await prefs.setString(_ownerKey, uid); // first run: claim what's here
      return false;
    }
    try {
      await _save(owner, prefs, isar);
    } catch (_) {
      /* disk full etc. — still never hand data to another student */
    }
    await _clearLive(prefs, isar);
    try {
      await _load(uid, prefs, isar);
    } catch (_) {/* unreadable saved set → start fresh; cloud merge refills */}
    await prefs.remove(mergedKey(uid));
    await prefs.setString(_ownerKey, uid);
    return true;
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/progress_by_student');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String _safe(String uid) =>
      uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<void> _save(
      String uid, SharedPreferences prefs, Isar? isar) async {
    final keys = <String, Object>{};
    for (final k in prefs.getKeys()) {
      if (!_isStudentKey(k)) continue;
      final v = prefs.get(k);
      if (v is bool) {
        keys[k] = {'t': 'b', 'v': v};
      } else if (v is int) {
        keys[k] = {'t': 'i', 'v': v};
      } else if (v is double) {
        keys[k] = {'t': 'd', 'v': v};
      } else if (v is String) {
        keys[k] = {'t': 's', 'v': v};
      } else if (v is List) {
        keys[k] = {'t': 'l', 'v': v.map((e) => '$e').toList()};
      }
    }
    Map<String, Object?>? profile;
    final topics = <Map<String, Object?>>[];
    if (isar != null) {
      final p = await isar.collection<StudentProfile>().where().findFirst();
      if (p != null) {
        profile = {
          'totalXp': p.totalXp,
          'currentTier': p.currentTier,
          'unlockedBadges': p.unlockedBadges,
          'currentStreakDays': p.currentStreakDays,
          'lastActiveYmd': p.lastActiveYmd,
        };
      }
      for (final t
          in await isar.collection<TopicProgress>().where().findAll()) {
        topics.add({
          'topicId': t.topicId,
          'hasViewedAr': t.hasViewedAr,
          'hasPassedQuiz': t.hasPassedQuiz,
          'arXpEarned': t.arXpEarned,
          'quizXpEarned': t.quizXpEarned,
          'synergyApplied': t.synergyApplied,
        });
      }
    }
    final d = await _dir();
    final f = File('${d.path}/${_safe(uid)}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'v': 1,
      'uid': uid,
      'saved_at': DateTime.now().toIso8601String(),
      'prefs': keys,
      'profile': profile,
      'topics': topics,
    }));
    await tmp.rename(f.path);
    _trim(d);
  }

  // Keep the newest [_maxSaved] saved students.
  static void _trim(Directory d) {
    try {
      final files = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in files.skip(_maxSaved)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  static Future<void> _clearLive(SharedPreferences prefs, Isar? isar) async {
    for (final k in prefs.getKeys().where(_isStudentKey).toList()) {
      await prefs.remove(k);
    }
    if (isar != null) {
      await isar.writeTxn(() async {
        await isar.collection<StudentProfile>().clear();
        await isar.collection<TopicProgress>().clear();
      });
    }
  }

  static Future<void> _load(
      String uid, SharedPreferences prefs, Isar? isar) async {
    final d = await _dir();
    final f = File('${d.path}/${_safe(uid)}.json');
    if (!f.existsSync()) return; // new on this phone → starts fresh
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final keys = (m['prefs'] as Map?) ?? const {};
    for (final e in keys.entries) {
      final k = '${e.key}';
      if (!_isStudentKey(k) || e.value is! Map) continue;
      final t = (e.value as Map)['t'];
      final v = (e.value as Map)['v'];
      if (t == 'b' && v is bool) {
        await prefs.setBool(k, v);
      } else if (t == 'i' && v is num) {
        await prefs.setInt(k, v.toInt());
      } else if (t == 'd' && v is num) {
        await prefs.setDouble(k, v.toDouble());
      } else if (t == 's' && v is String) {
        await prefs.setString(k, v);
      } else if (t == 'l' && v is List) {
        await prefs.setStringList(k, v.map((x) => '$x').toList());
      }
    }
    if (isar != null) {
      final p = m['profile'];
      final topics = (m['topics'] as List?) ?? const [];
      await isar.writeTxn(() async {
        if (p is Map) {
          final sp = StudentProfile()
            ..totalXp = (p['totalXp'] as num?)?.toInt() ?? 0
            ..currentTier = '${p['currentTier'] ?? 'Jigyasu'}'
            ..unlockedBadges = ((p['unlockedBadges'] as List?) ?? const [])
                .map((e) => '$e')
                .toList()
            ..currentStreakDays = (p['currentStreakDays'] as num?)?.toInt() ?? 0
            ..lastActiveYmd = (p['lastActiveYmd'] as num?)?.toInt() ?? 0;
          await isar.collection<StudentProfile>().put(sp);
        }
        final rows = <TopicProgress>[];
        for (final t in topics.whereType<Map>()) {
          final id = '${t['topicId'] ?? ''}';
          if (id.isEmpty) continue;
          rows.add(TopicProgress()
            ..topicId = id
            ..hasViewedAr = t['hasViewedAr'] == true
            ..hasPassedQuiz = t['hasPassedQuiz'] == true
            ..arXpEarned = (t['arXpEarned'] as num?)?.toInt() ?? 0
            ..quizXpEarned = (t['quizXpEarned'] as num?)?.toInt() ?? 0
            ..synergyApplied = t['synergyApplied'] == true);
        }
        if (rows.isNotEmpty) {
          await isar.collection<TopicProgress>().putAll(rows);
        }
      });
    }
    // The set is live again; the file is no longer needed.
    try {
      f.deleteSync();
    } catch (_) {}
  }
}
