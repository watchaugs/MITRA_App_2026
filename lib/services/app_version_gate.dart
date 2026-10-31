// ═══════════════════════════════════════════════════════════════════════════
// App version gate — keeps old installs working, forces an update ONLY when the
// backend says an app is too old to function safely.
//
// WHY: the app talks to a live backend. When the backend changes, an already-
// installed app can break even though its own code never changed. This gate
// lets the SERVER declare a minimum supported build. An app older than that
// shows a friendly "please update" screen instead of silently failing; a
// slightly-old app can show a soft "update available" nudge but keeps working.
//
// The check is best-effort: if the config call fails, the app assumes it is
// fine and continues (never block a student because config was unreachable).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';

class VersionStatus {
  final bool mustUpdate;   // hard gate — app too old to work
  final bool canUpdate;    // soft nudge — newer build exists
  final String updateUrl;
  final int currentBuild;
  final int minBuild;
  final int latestBuild;

  const VersionStatus({
    required this.mustUpdate,
    required this.canUpdate,
    required this.updateUrl,
    required this.currentBuild,
    required this.minBuild,
    required this.latestBuild,
  });

  static const ok = VersionStatus(
    mustUpdate: false, canUpdate: false, updateUrl: '',
    currentBuild: 0, minBuild: 0, latestBuild: 0,
  );
}

class AppVersionGate {
  // Reads the app's own build number, asks the backend for the version policy,
  // and compares. `state` scopes to the per-state config; '' uses defaults.
  static Future<VersionStatus> check(String state) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final res = await ApiService.instance.dio
          .get('/api/app-builder/config/${Uri.encodeComponent(state.isEmpty ? "default" : state)}');
      final data = (res.data is Map) ? res.data as Map : const {};

      final minBuild = (data['min_supported_build'] as num?)?.toInt() ?? 0;
      final latestBuild = (data['latest_build'] as num?)?.toInt() ?? 0;
      final updateUrl = (data['update_url'] as String?) ?? '';

      return VersionStatus(
        mustUpdate: currentBuild > 0 && minBuild > currentBuild,
        canUpdate: latestBuild > currentBuild,
        updateUrl: updateUrl,
        currentBuild: currentBuild,
        minBuild: minBuild,
        latestBuild: latestBuild,
      );
    } catch (_) {
      // Config unreachable → never block the student. Assume fine.
      return VersionStatus.ok;
    }
  }
}

// Checked once at startup. '' state is fine — defaults apply until the student's
// state is known, and the gate re-checks naturally on next launch.
final versionStatusProvider = FutureProvider<VersionStatus>((ref) async {
  return AppVersionGate.check('');
});
