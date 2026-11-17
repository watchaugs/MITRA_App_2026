// ═══════════════════════════════════════════════════════════════════════════
// Quiz rounds beyond the normal A–D question:
//   • Picture round  — tap the right picture (captions optional).
//   • Sequence round — tap the steps in the right order, then "Check".
// Pictures come from the on-device quiz pack (saved for offline use); if a
// picture hasn't been saved yet it loads from the network instead.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/colors.dart';
import '../../models/quiz_model.dart';
import '../../providers/tr_ext.dart';
import '../../stores/quiz_pack_store.dart';

/// A quiz picture: the saved copy when there is one, else the network.
class QuizImage extends StatelessWidget {
  final String url;
  final double? height;
  final BoxFit fit;
  const QuizImage(
      {super.key, required this.url, this.height, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    final store = QuizPackStore.instance;
    final file = store.cachedImage(url);
    Widget broken() => SizedBox(
          height: height ?? 80,
          child: const Center(
              child: Icon(Icons.image_not_supported_outlined,
                  color: Colors.white38, size: 32)),
        );
    if (file != null) {
      return Image.file(file,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => broken());
    }
    return CachedNetworkImage(
      imageUrl: store.imageUrl(url),
      height: height,
      fit: fit,
      placeholder: (_, __) => SizedBox(
          height: height ?? 80,
          child: const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)))),
      errorWidget: (_, __, ___) => broken(),
    );
  }
}

/// Picture round: 2–4 pictures in a grid. Same colours as the A–D options.
class PictureOptions extends StatelessWidget {
  final QuizQuestion question;
  final int? selected;
  final bool answered;
  final ValueChanged<int> onTap;
  final Color highlight;
  final bool isDark;
  const PictureOptions({
    super.key,
    required this.question,
    required this.selected,
    required this.answered,
    required this.onTap,
    required this.highlight,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final q = question;
    final hasCaptions = q.options.any((o) => o.trim().isNotEmpty);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: hasCaptions ? 0.82 : 1,
      ),
      itemCount: q.optionImages.length,
      itemBuilder: (ctx, i) {
        final isSel = selected == i;
        final isRight = i == q.correctAnswerIndex;
        Color border;
        double fade = 1;
        Color badge;
        if (!answered) {
          border = isSel
              ? highlight
              : MitraColors.border.withValues(alpha: 0.35);
          badge = isSel ? highlight : MitraColors.bgSurface;
        } else if (isSel) {
          border = isRight ? MitraColors.emerald : MitraColors.crimson;
          badge = border;
        } else {
          border = MitraColors.border.withValues(alpha: 0.1);
          badge = MitraColors.bgSurface;
          fade = 0.35;
        }
        final caption = q.options.length > i ? q.options[i].trim() : '';
        return Semantics(
          button: true,
          label: caption.isNotEmpty
              ? caption
              : String.fromCharCode(65 + i),
          child: GestureDetector(
            onTap: answered ? null : () => onTap(i),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: fade,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isSel
                      ? border.withValues(alpha: 0.15)
                      : MitraColors.bgCard.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(MitraRadius.md),
                  border: Border.all(color: border, width: isSel ? 2.5 : 1),
                ),
                child: Column(children: [
                  Expanded(
                    child: Stack(children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(MitraRadius.sm),
                          child: Container(
                            color: Colors.white,
                            child: QuizImage(url: q.optionImages[i]),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, color: badge),
                          child: answered && isSel
                              ? Icon(isRight ? Icons.check : Icons.close,
                                  size: 15, color: Colors.white)
                              : Text(String.fromCharCode(65 + i),
                                  style: TextStyle(
                                      fontFamily: 'SpaceMono',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: isSel && !answered
                                          ? Colors.black
                                          : Colors.white)),
                        ),
                      ),
                    ]),
                  ),
                  if (hasCaptions)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: 'Mukta',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E))),
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sequence round. Shuffles the steps once; the student taps them in order
/// (tap a numbered step again to take it back). [onOrder] gets the chosen
/// order (index in the right order for each position) once every step has a
/// number, else null. After answering, pass [result] (the order checked) to
/// show each position right (green) or wrong (red) — the right order itself
/// is not revealed, like the A–D questions.
class SequenceBoard extends ConsumerStatefulWidget {
  final QuizQuestion question;
  final List<int>? result;
  final ValueChanged<List<int>?> onOrder;
  final Color highlight;
  final bool isDark;
  const SequenceBoard({
    super.key,
    required this.question,
    required this.result,
    required this.onOrder,
    required this.highlight,
    required this.isDark,
  });

  @override
  ConsumerState<SequenceBoard> createState() => _SequenceBoardState();
}

class _SequenceBoardState extends ConsumerState<SequenceBoard> {
  late final List<int> _shown; // display slot → step index (right order)
  final List<int> _picked = []; // display slots, in the order tapped

  @override
  void initState() {
    super.initState();
    final n = widget.question.options.length;
    _shown = List<int>.generate(n, (i) => i);
    final rnd = math.Random();
    // Shuffle, but never show the steps already in the right order.
    for (int tries = 0; tries < 8; tries++) {
      _shown.shuffle(rnd);
      if (n < 2 || !_isIdentity(_shown)) break;
    }
    if (n >= 2 && _isIdentity(_shown)) {
      _shown.insert(0, _shown.removeLast());
    }
  }

  static bool _isIdentity(List<int> l) {
    for (int i = 0; i < l.length; i++) {
      if (l[i] != i) return false;
    }
    return true;
  }

  void _tap(int slot) {
    setState(() {
      if (_picked.contains(slot)) {
        _picked.remove(slot);
      } else {
        _picked.add(slot);
      }
    });
    _report();
  }

  void _clear() {
    setState(_picked.clear);
    _report();
  }

  void _report() {
    final done = _picked.length == _shown.length;
    widget.onOrder(done ? [for (final s in _picked) _shown[s]] : null);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1A1A2E);
    final result = widget.result;

    Widget tile(
        {required String text,
        required String badge,
        required Color border,
        required Color badgeColor,
        required Color badgeText,
        Color? fill,
        VoidCallback? onTap,
        IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            padding: const EdgeInsets.all(MitraSpacing.lg),
            decoration: BoxDecoration(
              color: fill ?? MitraColors.bgCard.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(MitraRadius.md),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: badgeColor),
                child: icon != null
                    ? Icon(icon, size: 16, color: Colors.white)
                    : Text(badge,
                        style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: badgeText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontFamily: 'Mukta',
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        color: textColor)),
              ),
            ]),
          ),
        ),
      );
    }

    // After "Check": the steps in the order the student chose.
    if (result != null) {
      return Column(children: [
        for (int pos = 0; pos < result.length; pos++)
          () {
            final ok = result[pos] == pos;
            final c = ok ? MitraColors.emerald : MitraColors.crimson;
            return tile(
              text: q.options[result[pos]],
              badge: '${pos + 1}',
              border: c,
              badgeColor: c,
              badgeText: Colors.white,
              fill: c.withValues(alpha: 0.12),
              icon: ok ? Icons.check : Icons.close,
            );
          }(),
      ]);
    }

    final left = _shown.length - _picked.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(Icons.touch_app_rounded, color: widget.highlight, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              left == 0
                  ? context.tr(ref, 'quiz_seq_ready',
                      'All set! Now check your order.')
                  : context.trp(ref, 'quiz_seq_hint',
                      'Tap the steps in the right order · {n} left',
                      {'n': '$left'}),
              style: TextStyle(
                  fontFamily: 'Mukta',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: textColor.withValues(alpha: 0.8)),
            ),
          ),
          if (_picked.isNotEmpty)
            TextButton.icon(
              onPressed: _clear,
              icon: Icon(Icons.restart_alt_rounded,
                  size: 18, color: widget.highlight),
              label: Text(context.tr(ref, 'quiz_seq_clear', 'Clear'),
                  style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      color: widget.highlight)),
            ),
        ]),
      ),
      for (int slot = 0; slot < _shown.length; slot++)
        () {
          final pos = _picked.indexOf(slot);
          final on = pos >= 0;
          return tile(
            text: q.options[_shown[slot]],
            badge: on ? '${pos + 1}' : '',
            border: on
                ? widget.highlight
                : MitraColors.border.withValues(alpha: 0.35),
            badgeColor: on ? widget.highlight : MitraColors.bgSurface,
            badgeText: Colors.black,
            fill: on ? widget.highlight.withValues(alpha: 0.12) : null,
            onTap: () => _tap(slot),
          );
        }(),
    ]);
  }
}
