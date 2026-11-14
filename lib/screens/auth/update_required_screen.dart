// ═══════════════════════════════════════════════════════════════════════════
// Force-update screen — shown ONLY when the backend reports the installed app
// is older than the minimum supported build. The student cannot proceed until
// they update, because the old app can no longer talk to the backend safely.
// This is the last-resort gate; most backend changes are made backward-safe so
// this never fires.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/colors.dart';

import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
class UpdateRequiredScreen extends ConsumerWidget {
  final String updateUrl;
  const UpdateRequiredScreen({super.key, required this.updateUrl});

  Future<void> _openStore() async {
    if (updateUrl.isEmpty) return;
    final uri = Uri.tryParse(updateUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MitraColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🚀', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 24),
                Text(
                  context.tr(ref, 'auth_update_mitra_to_continue', 'Update MITRA to continue'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr(ref, 'auth_a_newer_version_is_required_to', 'A newer version is required to keep learning. Please update the app — it only takes a moment.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _openStore,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MitraColors.saffron,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      context.tr(ref, 'auth_update_now', 'Update now'),
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
