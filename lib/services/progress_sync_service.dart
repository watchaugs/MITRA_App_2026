// ═══════════════════════════════════════════════════════════════════════════
// SERVICE: Cloud progress sync (XP / streak / module & quiz progress).
//
// WHY: Progress lived ONLY on-device (Isar XP + SharedPreferences modules), so a
// reinstall or a new phone showed zero XP — "XP resets on relogin". This syncs
// a SINGLE Firestore doc per student (student_progress/{uid}) so progress
// follows the account.
//
// COST: Push piggybacks the existing 10-day + month-end telemetry cadence (one
// write per flush), so it adds ~3 writes/month/student — negligible egress.
// Restore is ONE read on login. No per-event cloud writes.
//
// MERGE (max-wins): on login we MERGE cloud into local — higher XP, higher
// streak, union of badges, better quiz %, higher AR %, OR'd flags — so progress
// made offline on either device is never lost.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'achievement_engine.dart';
import '../stores/module_progress_store.dart';

class ProgressSyncService {
  final AchievementEngine _engine;
  final ModuleProgressStore _modules;
  ProgressSyncService(this._engine, this._modules);

  // Same '(default)' database instance the rest of the app writes to.
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: '(default)',
      ).collection('student_progress');

  // PUSH: write the full local snapshot to the cloud. Called from the existing
  // 10-day/month-end flush (and once right after a merge on login so the merged
  // state is immediately durable). Never throws — sync must not break the app.
  Future<void> push(String uid) async {
    if (uid.isEmpty) return;
    try {
      final profile = await _engine.exportProfile();
      final modules = _modules.exportProgress();
      await _col.doc(uid).set({
        'profile': profile,
        'modules': modules,
        'updatedAt': FieldValue.serverTimestamp(),
        'schema': 1,
      }, SetOptions(merge: true));
    } catch (_) {/* best-effort; next flush retries */}
  }

  // RESTORE: read the cloud snapshot and MERGE it into local (max-wins). Called
  // once on login. After merging, push once so the merged result is durable.
  Future<void> restoreAndMerge(String uid) async {
    if (uid.isEmpty) return;
    try {
      final snap = await _col.doc(uid).get();
      if (!snap.exists) return; // fresh account — nothing to restore
      final data = snap.data() ?? const {};

      final profile = (data['profile'] as Map?)?.cast<String, dynamic>();
      if (profile != null) await _engine.mergeProfile(profile);

      final modules = (data['modules'] as Map?)?.cast<String, dynamic>();
      if (modules != null) await _modules.mergeProgress(modules);

      // Persist the merged state back so both sides converge.
      await push(uid);
    } catch (_) {/* never block login on a sync failure */}
  }
}

final progressSyncServiceProvider = Provider<ProgressSyncService>((ref) {
  return ProgressSyncService(
    ref.watch(achievementEngineProvider),
    ref.watch(moduleProgressStoreProvider),
  );
});
