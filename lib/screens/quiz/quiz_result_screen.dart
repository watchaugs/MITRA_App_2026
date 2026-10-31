// ═══════════════════════════════════════════════════════
// SCREEN: Quiz Result
// Features: score ring, XP chip, full question review
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/tr_ext.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../widgets/language_alphabet_background.dart';
import '../../constants/colors.dart';
import '../../models/quiz_model.dart';
import 'package:lottie/lottie.dart';

class QuizResultScreen extends ConsumerWidget {
  final int score;
  final int total;
  final int xpEarned;
  final String quizId;
  final List<QuizQuestion> questions;
  final List<int?> studentAnswers;

  const QuizResultScreen({
    super.key,
    required this.score,
    required this.total,
    required this.xpEarned,
    required this.quizId,
    required this.questions,
    required this.studentAnswers,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = total > 0 ? (score / total * 100).toInt() : 0;

    // ✨ Mastery Gate Logic
    final isMastered = score == total;

    final emoji = isMastered ? '🏆' : '⚠️';
    final message =
        isMastered ? '100% Mastery Achieved!' : 'Module Not Mastered';

    // Streak: consecutive correct from start
    int streak = 0;
    for (int i = 0; i < questions.length; i++) {
      if (studentAnswers[i] == questions[i].correctAnswerIndex) {
        streak++;
      } else {
        break;
      }
    }

    // Quiz result screen lives outside StudentShell — no shared background layer.
    // Wrap in a Stack so LanguageAlphabetBackground shows behind MitraScaffold.
    return Stack(
      children: [
        const Positioned.fill(child: LanguageAlphabetBackground()),
        MitraScaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(MitraSpacing.xl),
              child: Column(
                children: [
                  // ── Score summary ──────────────────────
                  Text(emoji, style: const TextStyle(fontSize: 72)),
                  const SizedBox(height: MitraSpacing.sm),
                  Text(message,
                      style: const TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          color: MitraColors.textPrimary)),

                  const SizedBox(height: MitraSpacing.xl),

                  // Score ring
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isMastered
                              ? MitraColors.emerald
                              : MitraColors.crimson,
                          width: 6),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$pct%',
                            style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontWeight: FontWeight.w800,
                                fontSize: 34,
                                color: isMastered
                                    ? MitraColors.emerald
                                    : MitraColors.crimson)),
                        Text('$score/$total',
                            style: const TextStyle(
                                fontFamily: 'Mukta',
                                fontSize: 13,
                                color: MitraColors.textMuted)),
                      ],
                    ),
                  ),

                  const SizedBox(height: MitraSpacing.lg),

                  // ── Stats Row ────────────────────────────────────
                  if (isMastered)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: MitraColors.gold.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(MitraRadius.pill),
                            border: Border.all(
                                color: MitraColors.gold.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '+$xpEarned XP',
                            style: const TextStyle(
                                fontFamily: 'Baloo2',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: MitraColors.gold),
                          ),
                        ),
                        if (streak > 1) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  MitraColors.saffron.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(MitraRadius.pill),
                              border: Border.all(
                                  color: MitraColors.saffron
                                      .withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              '🔥 $streak streak',
                              style: const TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: MitraColors.saffron),
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text(
                        'You must score 100% to unlock the next module. Please re-watch the AR lesson and try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 14,
                          color: MitraColors.textSecondary,
                        ),
                      ),
                    ),

                  const SizedBox(height: MitraSpacing.xl),

                  // ── Conditional Buttons (The Gate) ────────────────────────────
                  if (!isMastered)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: GestureDetector(
                        // ✨ Forces them back to the AR Viewer
                        onTap: () => context.go('/student/ar/$quizId'),
                        child: Container(
                          decoration: BoxDecoration(
                              color: MitraColors.crimson,
                              borderRadius:
                                  BorderRadius.circular(MitraRadius.pill),
                              boxShadow: [
                                BoxShadow(
                                  color: MitraColors.crimson
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ]),
                          alignment: Alignment.center,
                          child: Text(
                              context.tr(ref, 'quiz_rewatch_ar',
                                  '🔄 Re-watch AR Lesson'),
                              style: const TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: Colors.white)),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: GestureDetector(
                            onTap: () => context.go('/student/home'),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: MitraColors.gradientSaffron),
                                borderRadius:
                                    BorderRadius.circular(MitraRadius.pill),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                  context.tr(
                                      ref, 'quiz_back_home', 'Back to Home'),
                                  style: const TextStyle(
                                      fontFamily: 'Baloo2',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: Colors.white)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => context.go('/student/learn'),
                          child: Text(
                              context.tr(
                                  ref, 'quiz_next_module', 'Next Module'),
                              style: const TextStyle(
                                  fontFamily: 'Mukta',
                                  fontSize: 14,
                                  color: MitraColors.sky)),
                        ),
                      ],
                    ),

                  const SizedBox(height: MitraSpacing.xl),

                  // ── Question Review ────────────────────
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Review Answers',
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: MitraColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: MitraSpacing.md),

                  ...List.generate(questions.length, (i) {
                    final q = questions[i];
                    final studentAns = studentAnswers[i];
                    final isCorrect = studentAns == q.correctAnswerIndex;
                    return _ReviewItem(
                      index: i,
                      question: q,
                      studentAnswer: studentAns,
                      isCorrect: isCorrect,
                    );
                  }),

                  const SizedBox(height: MitraSpacing.lg),
                ],
              ),
            ),
          ),
        ), // closes MitraScaffold

        // ✨ LOTTIE CONFETTI BLAST (Only fires on 100% Mastery)
        if (isMastered)
          Positioned.fill(
            child: IgnorePointer(
              // Ensures the animation doesn't block screen taps
              child: Lottie.asset(
                'assets/animations/Confetti.json', // ✨ Using your local file
                fit: BoxFit
                    .cover, // Stretches to the edges so the cannons hit the corners
                repeat: false, // Ensures it only blasts once!
              ),
            ),
          ),
      ],
    ); // closes Stack
  }
}

// Collapsed by default; tap to expand. Explanation is shown ONLY when the
// student answered correctly — wrong answers never reveal the explanation.
class _ReviewItem extends StatefulWidget {
  final int index;
  final QuizQuestion question;
  final int? studentAnswer;
  final bool isCorrect;

  const _ReviewItem({
    required this.index,
    required this.question,
    required this.studentAnswer,
    required this.isCorrect,
  });

  @override
  State<_ReviewItem> createState() => _ReviewItemState();
}

class _ReviewItemState extends State<_ReviewItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final isCorrect = widget.isCorrect;
    final accent = isCorrect ? MitraColors.emerald : MitraColors.crimson;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(MitraRadius.md),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(MitraSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Collapsed header row: Q number + verdict + expand chevron.
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                      ),
                      child: Text(
                        'Q${widget.index + 1}',
                        style: TextStyle(
                          fontFamily: 'SpaceMono',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isCorrect
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: accent,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCorrect ? 'Correct' : 'Incorrect',
                      style: TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: accent.withValues(alpha: 0.7),
                    ),
                  ],
                ),

                // Expanded body.
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Text(
                    q.questionText,
                    style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: MitraColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isCorrect) ...[
                    // Correct answer → reveal the answer AND the explanation.
                    _ReviewAnswerRow(
                      label: 'Correct',
                      answer: q.options[q.correctAnswerIndex],
                      color: MitraColors.emerald,
                    ),
                    if (q.explanation != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_outline,
                              color: MitraColors.indigoLight, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              q.explanation!,
                              style: const TextStyle(
                                fontFamily: 'Mukta',
                                fontSize: 12,
                                color: MitraColors.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    // Wrong answer → show ONLY what the student picked. Never the
                    // correct answer, never the explanation. Encourage a retry.
                    if (widget.studentAnswer != null)
                      _ReviewAnswerRow(
                        label: 'Your answer',
                        answer: q.options[widget.studentAnswer!],
                        color: MitraColors.crimson,
                      ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.thumb_up_alt_outlined,
                            color: MitraColors.saffron, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Try again',
                          style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: MitraColors.saffron,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewAnswerRow extends StatelessWidget {
  final String label;
  final String answer;
  final Color color;

  const _ReviewAnswerRow({
    required this.label,
    required this.answer,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontFamily: 'Mukta',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.8),
          ),
        ),
        Expanded(
          child: Text(
            answer,
            style: TextStyle(
              fontFamily: 'Mukta',
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
