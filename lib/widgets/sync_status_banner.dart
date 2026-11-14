// ═══════════════════════════════════════════════════════
// SyncStatusBanner — surfaces the existing Hive-backed
// offline queue (lib/stores/offline_store.dart) to the
// student/teacher. Shows nothing when everything is synced;
// shows offline/pending/syncing/error state with a manual
// "Retry" action otherwise.
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/colors.dart';
import '../stores/offline_store.dart';

import '../providers/tr_ext.dart';
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider);

    // Nothing pending, online, no error — stay invisible and take no space.
    if (offline.isOnline &&
        offline.queue.isEmpty &&
        offline.syncStatus != SyncStatus.error) {
      return const SizedBox.shrink();
    }

    final Color color;
    final IconData icon;
    final String label;
    bool showRetry = false;

    if (!offline.isOnline) {
      color = MitraColors.crimson;
      icon = Icons.cloud_off_rounded;
      label = offline.queue.isEmpty
          ? context.tr(ref, 'common_youre_offline', "You're offline")
          : context.trp(ref, 'common_youre_offline_queue_length_waiting_t', "You're offline · {queue_length} waiting to sync", {'queue_length': "${offline.queue.length}"});
    } else if (offline.syncStatus == SyncStatus.syncing) {
      color = MitraColors.sky;
      icon = Icons.sync_rounded;
      label =
          offline.queue.length == 1
              ? context.tr(ref, 'common_syncing_1_item', 'Syncing 1 item…')
              : context.trp(ref, 'common_syncing_n_items', 'Syncing {count} items…', {'count': '${offline.queue.length}'});
    } else if (offline.queue.isNotEmpty) {
      color = MitraColors.gold;
      icon = Icons.cloud_upload_rounded;
      label =
          offline.queue.length == 1
              ? context.tr(ref, 'common_1_item_pending_sync', '1 item pending sync')
              : context.trp(ref, 'common_n_items_pending_sync', '{count} items pending sync', {'count': '${offline.queue.length}'});
      showRetry = true;
    } else {
      color = MitraColors.crimson;
      icon = Icons.error_outline_rounded;
      label = context.tr(ref, 'common_sync_error_will_retry_automatically', 'Sync error — will retry automatically');
    }

    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(MitraRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ),
            if (showRetry)
              GestureDetector(
                onTap: () => ref.read(offlineProvider.notifier).retryNow(),
                child: Text(
                  context.tr(ref, 'btn_retry', 'Retry'),
                  style: TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                      decoration: TextDecoration.underline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
