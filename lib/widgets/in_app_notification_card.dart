// ═══════════════════════════════════════════════════════════════════════════
// In-app notification card — the fully-styled notification shown while the app
// is OPEN (foreground). Unlike the OS tray notification (whose text colours the
// OS controls), this card honours every styling field the dashboard sends:
// accent colour, emoji badge, banner image, title and body.
//
// Called from main.dart's FCM onMessage handler via showInAppNotificationCard().
// Tapping it deep-links the same way a tray tap does; it also auto-dismisses.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

void showInAppNotificationCard(BuildContext context, RemoteMessage msg) {
  final n = msg.notification;
  if (n == null) return;
  final data = msg.data;

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _InAppCard(
      title: n.title ?? 'MITRA',
      body: n.body ?? '',
      colorHex: (data['color'] ?? '').toString(),
      imageUrl: (data['image_url'] ?? '').toString(),
      emoji: (data['emoji'] ?? '📢').toString(),
      onTap: () {
        entry.remove();
        final type = data['deep_link_type']?.toString();
        final id = data['deep_link_id']?.toString();
        if (type != null && id != null && id.isNotEmpty) {
          if (type == 'quiz') GoRouter.of(context).go('/quiz/$id');
          if (type == 'ar_topic') GoRouter.of(context).go('/student/ar/$id');
        }
      },
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _InAppCard extends StatefulWidget {
  final String title, body, colorHex, imageUrl, emoji;
  final VoidCallback onTap, onDismiss;
  const _InAppCard({
    required this.title,
    required this.body,
    required this.colorHex,
    required this.imageUrl,
    required this.emoji,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppCard> createState() => _InAppCardState();
}

class _InAppCardState extends State<_InAppCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();
  Timer? _auto;

  Color get _accent {
    final h = widget.colorHex;
    if (h.startsWith('#') && h.length == 7) {
      return Color(int.parse('FF${h.substring(1)}', radix: 16));
    }
    return const Color(0xFFFF9933); // saffron default
  }

  @override
  void initState() {
    super.initState();
    // Auto-dismiss after 6s if the student doesn't interact.
    _auto = Timer(const Duration(seconds: 6), _dismiss);
  }

  Future<void> _dismiss() async {
    _auto?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: const ValueKey('in_app_notif'),
            direction: DismissDirection.up,
            onDismissed: (_) {
              _auto?.cancel();
              widget.onDismiss();
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF14141C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: Image.network(
                          widget.imageUrl,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.5)),
                            ),
                            child: Text(widget.emoji,
                                style: const TextStyle(fontSize: 20)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Baloo2',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Mukta',
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _dismiss,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.close,
                                  size: 18, color: Colors.white38),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
