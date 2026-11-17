// ═══════════════════════════════════════════════════════════════════════════
// SERVICE: Cloud progress sync (XP / streak / module & quiz progress).
//
// WHY: Progress lived ONLY on-device (Isar XP + SharedPreferences modules), so a
// reinstall or a new phone showed zero XP — "XP resets on relogin". This syncs
// a SINGLE Firestore doc per student (student_progress/{uid}) so progress
// follows the account.
//
// COST: one write after each login merge, at logout, and every 10 days
// (pushIfDue at app start) — a few writes/month/student. Restore is ONE read
// on login. No per-event cloud writes.
//
// MERGE (max-wins): on login we MERGE cloud into local — higher XP, higher
// streak, union of badges, better quiz %, higher AR %, OR'd flags — so progress
// made offline on either device is never lost.
//
// SHARED PHONES: merge and push only touch the live set when it belongs to
// that student (stores/device_owner.dart), so one student's progress is never
// merged into or uploaded as another's. Push runs after the login merge, at
// logout, and every 10 days (pushIfDue).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'achievement_engine.dart';
import '../stores/device_owner.dart';
import 'territory_service.dart'; // TerritoryGate (home-state rule)
import '../stores/module_progress_store.dart';
import '../theme/theme_provider.dart'; // sharedPreferencesProvider

class ProgressSyncService {
  final AchievementEngine _engine;
  final ModuleProgressStore _modules;
  final SharedPreferences _prefs;
  ProgressSyncService(this._engine, this._modules, this._prefs);

  static const Duration _pushEvery = Duration(days: 10);
  String _mergedKey(String uid) => DeviceOwner.mergedKey(uid);
  String _pushedKey(String uid) => 'progress_pushed_at_$uid';
  Future<void>? _restoring; // one login merge at a time per student
  String? _restoringUid;

  bool _isLiveOwner(String uid) => DeviceOwner.ownerOf(_prefs) == uid;

  // Same '(default)' database instance the rest of the app writes to.
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: '(default)',
      ).collection('student_progress');

  // PUSH: write the full local snapshot to the cloud. Called right after the
  // login merge, at logout, and every 10 days via pushIfDue (one write each).
  // Never throws — sync must not break the app.
  Future<void> push(String uid) async {
    if (uid.isEmpty) return;
    await DeviceOwner.settled();
    // Never upload the live set as someone else's, and never before this
    // student's cloud copy has been merged in (that could lower cloud XP).
    if (!_isLiveOwner(uid) || _prefs.getBool(_mergedKey(uid)) != true) return;
    if (!TerritoryGate.syncAllowed) return; // only from the home state
    try {
      final profile = await _engine.exportProfile();
      final modules = _modules.exportProgress();
      await _col.doc(uid).set({
        'profile': profile,
        'modules': modules,
        'updatedAt': FieldValue.serverTimestamp(),
        'schema': 1,
      }, SetOptions(merge: true));
      await _prefs.setString(_pushedKey(uid), DateTime.now().toIso8601String());
    } catch (_) {/* best-effort; next flush retries */}
  }

  /// Called at every sign-in / app start: merges once if this phone never has
  /// for this student, else pushes when the last push is 10+ days old.
  Future<void> pushIfDue(String uid) async {
    if (uid.isEmpty) return;
    await DeviceOwner.settled();
    if (!_isLiveOwner(uid)) return;
    if (_prefs.getBool(_mergedKey(uid)) != true) {
      await restoreAndMerge(uid);
      return;
    }
    final last = DateTime.tryParse(_prefs.getString(_pushedKey(uid)) ?? '');
    if (last == null || DateTime.now().difference(last) >= _pushEvery) {
      await push(uid);
    }
  }

  // RESTORE: read the cloud snapshot and MERGE it into local (max-wins). Called
  // once on login. After merging, push once so the merged result is durable.
  Future<void> restoreAndMerge(String uid) {
    if (uid.isEmpty) return Future.value();
    final running = _restoring;
    if (running != null && _restoringUid == uid) return running;
    _restoringUid = uid;
    final f = _restore(uid);
    _restoring = f;
    return f.whenComplete(() {
      if (identical(_restoring, f)) _restoring = null;
    });
  }

  Future<void> _restore(String uid) async {
    // Wait for the sign-in switch so we merge into THIS student's set.
    await DeviceOwner.settled();
    if (!_isLiveOwner(uid)) return;
    if (!TerritoryGate.syncAllowed) return; // merged later, back home
    try {
      final snap = await _col.doc(uid).get();
      if (snap.exists) {
        final data = snap.data() ?? const {};

        final profile = (data['profile'] as Map?)?.cast<String, dynamic>();
        if (profile != null) await _engine.mergeProfile(profile);

        final modules = (data['modules'] as Map?)?.cast<String, dynamic>();
        if (modules != null) await _modules.mergeProgress(modules);
      }
      // Only a copy from the server proves the cloud has nothing newer.
      // (Offline, the cached copy is merged but nothing is uploaded.)
      if (snap.metadata.isFromCache) return;
      // Merged (or a fresh account): pushes are safe from now on.
      await _prefs.setBool(_mergedKey(uid), true);

      // Persist the merged state back so both sides converge.
      await push(uid);
    } catch (_) {/* never block login on a sync failure */}
  }
}

final progressSyncServiceProvider = Provider<ProgressSyncService>((ref) {
  return ProgressSyncService(
    ref.watch(achievementEngineProvider),
    ref.watch(moduleProgressStoreProvider),
    ref.watch(sharedPreferencesProvider),
  );
});
