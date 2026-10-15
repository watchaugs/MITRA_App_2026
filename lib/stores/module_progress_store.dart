// ═══════════════════════════════════════════════════════
// MITRA — Module Progress Store (device-local gating state)
// ═══════════════════════════════════════════════════════
//
// WHAT THIS IS
//   The Learn tab gates modules: the NEXT module unlocks only after the
//   CURRENT module's quiz hits 100% (best attempt kept). It also hides a
//   module's quiz until the student has launched + watched its AR lesson once,
//   and shows a score badge (100% once mastered, otherwise the best % so far).
//
//   This file holds that per-module state ON THE DEVICE (SharedPreferences —
//   fast, offline, zero backend cost). It is the single source of truth the
//   Learn screen reads for locks and badges.
//
// CLOUD SYNC (no new network calls here)
//   The raw quiz attempts already ride to the backend through
//   quiz_offline_service.dart, which batches them on an interval. The backend
//   remaps those into student analytics. So this store does NOT make its own
//   network calls — it mirrors what the batched attempts already carry. If the
//   app is reinstalled, the device-local gates reset, but the cloud still has
//   the attempt history (and can be used to rehydrate later if you choose).
//
// KEYS (per module/quiz id)
//   mp_best_<id>   : int   best percentage score 0..100
//   mp_arseen_<id> : bool  AR lesson for this module launched + watched once
//
//   A module is "mastered" when mp_best_<id> == 100.
// ═══════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_provider.dart'; // sharedPreferencesProvider

String _bestKey(String id) => 'mp_best_$id';
String _arSeenKey(String id) => 'mp_arseen_$id';

/// Immutable snapshot of one module's progress.
class ModuleProgress {
  final String id;
  final int bestPct; // 0..100
  final bool arWatched;

  const ModuleProgress({
    required this.id,
    this.bestPct = 0,
    this.arWatched = false,
  });

  bool get mastered => bestPct >= 100;
  bool get attempted => bestPct > 0;
}

class ModuleProgressStore {
  final SharedPreferences _prefs;
  ModuleProgressStore(this._prefs);

  // ── Reads ──────────────────────────────────────────────
  int bestPct(String id) {
    if (id.isEmpty) return 0;
    final v = _prefs.getInt(_bestKey(id)) ?? 0;
    return v.clamp(0, 100);
  }

  bool isMastered(String id) => bestPct(id) >= 100;

  bool arWatched(String id) {
    if (id.isEmpty) return false;
    return _prefs.getBool(_arSeenKey(id)) ?? false;
  }

  ModuleProgress read(String id) => ModuleProgress(
        id: id,
        bestPct: bestPct(id),
        arWatched: arWatched(id),
      );

  // ── Writes ─────────────────────────────────────────────
  /// Record a quiz result. Keeps the BEST attempt — a lower later attempt
  /// never downgrades a module that was already mastered.
  Future<void> recordQuiz(String id, int score, int total) async {
    if (id.isEmpty || total <= 0) return;
    final pct = ((score / total) * 100).round().clamp(0, 100);
    final prev = bestPct(id);
    if (pct > prev) {
      await _prefs.setInt(_bestKey(id), pct);
    }
  }

  /// Mark that the student has launched + watched this module's AR lesson once.
  /// This is what makes the quiz appear as its own list item.
  Future<void> markArWatched(String id) async {
    if (id.isEmpty) return;
    if (_prefs.getBool(_arSeenKey(id)) == true) return;
    await _prefs.setBool(_arSeenKey(id), true);
  }
}

/// Provider for the store itself (reads SharedPreferences synchronously).
final moduleProgressStoreProvider = Provider<ModuleProgressStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ModuleProgressStore(prefs);
});

/// A tiny tick that bumps whenever progress changes, so widgets watching it
/// rebuild (locks/badges refresh) without us wiring a full StateNotifier map.
final moduleProgressTickProvider = StateProvider<int>((ref) => 0);
