import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/colors.dart';
import '../../../services/api_service.dart';
import '../../../stores/auth_store.dart';

/// Shows the MITRA feedback / NPS sheet. Call from any button:
///   showFeedbackDialog(context, ref, screen: 'settings');
Future<void> showFeedbackDialog(
  BuildContext context,
  WidgetRef ref, {
  String screen = 'app',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FeedbackDialog(parentRef: ref, screen: screen),
  );
}

class _FeedbackDialog extends StatefulWidget {
  final WidgetRef parentRef;
  final String screen;
  const _FeedbackDialog({required this.parentRef, required this.screen});
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  int? _score;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_score == null) return;
    setState(() => _sending = true);
    final user = widget.parentRef.read(currentUserProvider);
    final payload = <String, dynamic>{
      'type': 'nps',
      'nps_score': _score,
      'message': _comment.text.trim(),
      'screen': widget.screen,
      'state': user?.assignedState,
      'class_grade': user?.classGrade,
      'student_id': user?.id,
    };
    try {
      await FeedbackAPI.submit(payload);
    } catch (_) {/* never block the student on a failed send */}
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thank you for your feedback!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    return AlertDialog(
      backgroundColor: cs.surface,
      title: Text('Share your feedback',
          style: TextStyle(
              fontFamily: 'Mukta',
              fontWeight: FontWeight.w700,
              color: onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How likely are you to recommend MITRA to a friend?',
                style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 14,
                    color: onSurface.withValues(alpha: 0.85))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(11, (i) {
                final selected = _score == i;
                return GestureDetector(
                  onTap: () => setState(() => _score = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? MitraColors.saffron
                          : onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected
                              ? MitraColors.saffron
                              : onSurface.withValues(alpha: 0.15)),
                    ),
                    child: Text('$i',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : onSurface)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Not likely',
                    style: TextStyle(
                        fontSize: 11, color: onSurface.withValues(alpha: 0.5))),
                Text('Very likely',
                    style: TextStyle(
                        fontSize: 11, color: onSurface.withValues(alpha: 0.5))),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _comment,
              maxLines: 3,
              maxLength: 500,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText: "Anything you'd like to tell us? (optional)",
                hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.4)),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _sending ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel')),
        TextButton(
          onPressed: (_score == null || _sending) ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send',
                  style: TextStyle(
                      color: MitraColors.saffron, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
