import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

/// Active notifications pushed/scheduled from the dashboard.
final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await NotificationsAPI.list(status: 'active');
    final raw = res.data is Map ? res.data['data'] : null;
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  } catch (_) {/* fail silent */}
  return const [];
});
