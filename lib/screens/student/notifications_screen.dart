import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/colors.dart';
import '../../services/api_service.dart';
import '../../demo/demo_data.dart';
import '../../theme/theme_provider.dart';

/// Notifications pushed/scheduled from the dashboard (`/api/notifications`).
/// Demo-safe: seeded list in presentation mode, empty on error.
final studentNotificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (kPresentationMode) {
    return [
      {
        'title': 'New AR lesson: Cell Division',
        'body':
            'A new 3D lesson is now available in Science. Open Learn to explore.',
        'created_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      },
      {
        'title': 'Weekly quiz is live',
        'body': 'Your class quiz is open. Earn XP before Sunday!',
        'created_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      },
    ];
  }
  try {
    final res = await NotificationsAPI.list(status: 'active');
    final raw = res.data is Map ? res.data['data'] : null;
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  } catch (_) {/* fail silent → empty state */}
  return const [];
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final async = ref.watch(studentNotificationsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              color: ThemeHelper.ctxGlassFill(context),
              padding: const EdgeInsets.all(MitraSpacing.lg),
              child: Row(children: [
                const Text('🔔', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Text('Notifications',
                    style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: onSurface)),
              ]),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(
                    child:
                        CircularProgressIndicator(color: MitraColors.saffron)),
                error: (_, __) => _empty(onSurface),
                data: (items) {
                  if (items.isEmpty) return _empty(onSurface);
                  return RefreshIndicator(
                    color: MitraColors.saffron,
                    onRefresh: () async =>
                        ref.invalidate(studentNotificationsProvider),
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        MitraSpacing.lg,
                        MitraSpacing.lg,
                        MitraSpacing.lg,
                        MediaQuery.paddingOf(context).bottom + MitraSpacing.lg,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _NotifCard(item: items[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(Color onSurface) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('No notifications yet',
                style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 14,
                    color: onSurface.withValues(alpha: 0.6))),
          ],
        ),
      );
}

class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _NotifCard({required this.item});

  String _timeAgo() {
    final raw = item['created_at'];
    DateTime? dt;
    if (raw is String) {
      dt = DateTime.tryParse(raw);
    } else if (raw is Map && raw['_seconds'] is int) {
      dt = DateTime.fromMillisecondsSinceEpoch((raw['_seconds'] as int) * 1000);
    }
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = (item['title'] ?? '').toString();
    final body = (item['body'] ?? item['message'] ?? '').toString();
    final time = _timeAgo();

    return Container(
      padding: const EdgeInsets.all(MitraSpacing.md),
      decoration: BoxDecoration(
        color: ThemeHelper.ctxGlassFill(context),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📣', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: onSurface)),
                    ),
                    if (time.isNotEmpty)
                      Text(time,
                          style: TextStyle(
                              fontFamily: 'Mukta',
                              fontSize: 11,
                              color: onSurface.withValues(alpha: 0.5))),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 13,
                          color: onSurface.withValues(alpha: 0.75))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
