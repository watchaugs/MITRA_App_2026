// ═══════════════════════════════════════════════════════
// SCREEN: Quiz Screen
// Features: answer reveal, explanation, dot indicators,
//           locked options after answer, question review
// ═══════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✨ REQUIRED FOR HAPTIC BUZZER
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../widgets/language_alphabet_background.dart';
import '../../constants/colors.dart';
import '../../services/quiz_offline_service.dart';
import '../../stores/module_progress_store.dart';
import '../../stores/quiz_pack_store.dart';
import '../../models/quiz_model.dart';
import '../../demo/demo_data.dart';
import '../../theme/theme_provider.dart';
//import '../../providers/telemetry_provider.dart';
import '../../stores/auth_store.dart';
import '../../services/achievement_engine.dart'; // ✨ Added Engine Import

class QuizScreen extends ConsumerStatefulWidget {
  final String quizId;
  const QuizScreen({super.key, required this.quizId});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  List<QuizQuestion> _questions = [];
  int _current = 0;
  int? _selected;
  bool _loading = true;
  int _score = 0;
  bool _answered = false;
  bool _canAdvance = false; // ✨ NEW: Locks the next button to enforce reading
  DateTime _quizStartTime = DateTime.now();
  DateTime _questionStartTime = DateTime.now();

  final List<int?> _studentAnswers = [];
  final List<Map<String, dynamic>> _mcqResponses = [];

  // ✨ Flash Animation Controllers
  late AnimationController _flashCtrl;
  late Animation<Color?> _flashColor;

  @override
  void initState() {
    super.initState();
    _loadQuiz();

    _flashCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _flashColor = ColorTween(
      begin: Colors.transparent,
      end: Colors.red.withValues(alpha: 0.65),
    ).animate(_flashCtrl);
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    super.dispose();
  }

  Future<void> _playEmergencyFlash() async {
    for (int i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      await _flashCtrl.forward();
      await _flashCtrl.reverse();
    }
  }

  Future<void> _loadQuiz() async {
    // Presentation mode: play seeded questions for THIS quiz id, no network.
    if (kPresentationMode) {
      final demo = kDemoQuestions[widget.quizId];
      setState(() {
        _questions = List.from(demo ?? _mockQuestions);
        _studentAnswers.addAll(List.filled(_questions.length, null));
        _loading = false;
        _quizStartTime = DateTime.now();
      });
      return;
    }
    // Read questions from the on-device quiz pack. The pack is downloaded ONCE
    // per state (questions are fixed for the year) and cached on the device, so
    // taking a quiz makes NO network call. Only results sync back (batched).
    try {
      final state = ref.read(currentUserProvider)?.assignedState ?? '';
      final store = ref.read(quizPackStoreProvider);
      await store.ensurePack(state); // no-op if already on the device
      final loaded = await store.questionsFor(widget.quizId);
      setState(() {
        _questions = List.from(loaded); // may be empty → clean empty state
        _studentAnswers.addAll(List.filled(_questions.length, null));
        _loading = false;
        _quizStartTime = DateTime.now();
      });
    } catch (_) {
      // Pack missing/unreadable → show the clean empty state, not demo content.
      setState(() {
        _questions = const [];
        _loading = false;
        _quizStartTime = DateTime.now();
      });
    }
  }

  static final _mockQuestions = [
    const QuizQuestion(
      questionText: 'Which organelle is called the powerhouse of the cell?',
      options: ['Nucleus', 'Mitochondria', 'Ribosome', 'Chloroplast'],
      correctAnswerIndex: 1,
      explanation:
          'The mitochondria produces ATP energy for the cell through cellular respiration.',
    ),
    const QuizQuestion(
      questionText: 'What is the chemical formula for water?',
      options: ['CO2', 'H2O2', 'H2O', 'NaCl'],
      correctAnswerIndex: 2,
      explanation: 'Water is made of 2 hydrogen atoms and 1 oxygen atom — H2O.',
    ),
    const QuizQuestion(
      questionText: 'How many planets are in our solar system?',
      options: ['7', '8', '9', '10'],
      correctAnswerIndex: 1,
      explanation:
          'There are 8 planets. Pluto was reclassified as a dwarf planet in 2006.',
    ),
  ];

  // Called when student taps an option — locks in the answer and reveals result
  void _selectAnswer(int idx) {
    if (_answered) return;
    final timeMs = DateTime.now().difference(_questionStartTime).inMilliseconds;
    final isCorrect = idx == _questions[_current].correctAnswerIndex;
    setState(() {
      _selected = idx;
      _answered = true;
      _canAdvance =
          !isCorrect; // ✨ Instantly advance on wrong, lock on correct!
      _studentAnswers[_current] = idx;
      if (isCorrect) _score++;
      _mcqResponses.add({
        'question_id': 'q${_current + 1}',
        'answer': ['A', 'B', 'C', 'D'][idx],
        'correct': isCorrect,
        'time_ms': timeMs,
      });
    });

    if (isCorrect) {
      // ✨ Forces the student to read the dynamic explanation before advancing
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _canAdvance = true;
          });
        }
      });
    } else {
      // ✨ Trigger flash & haptic feedback on wrong answer
      _playEmergencyFlash();
    }
  }

  void _next() {
    if (!_answered) return;

    if (_current < _questions.length - 1) {
      setState(() {
        _current++;
        _selected = null;
        _answered = false;
        _questionStartTime = DateTime.now();
      });
    } else {
      // Submit
      final durationSeconds =
          DateTime.now().difference(_quizStartTime).inSeconds;
      final xpEarned = _score * 50;

      // Recorded locally only — no network call here. A background
      // scheduler (quiz_offline_service.dart) batches this with other
      // attempts and sends them together, once a day.
      final user = ref.read(currentUserProvider);
      unawaited(QuizOfflineDb.instance.recordAttempt(
        quizId: widget.quizId,
        studentId: user?.id ?? 'anonymous',
        state: user?.assignedState ?? '',
        district: user?.assignedDistrict ?? '',
        classGrade: user?.classGrade ?? '',
        score: _score,
        maxScore: _questions.length,
        questionsAttempted: _questions.length,
        correctAnswers: _score,
        timeTakenSecs: durationSeconds,
        appLanguage: user?.languagePreference ?? 'en',
      ));

      // Gating: keep the BEST percentage for this module (quizId == module id).
      // 100% unlocks the next module in the Learn list. This is device-local;
      // the raw attempt above already syncs to the cloud via the batch service.
      unawaited(
        ref.read(moduleProgressStoreProvider).recordQuiz(
              widget.quizId,
              _score,
              _questions.length,
            ),
      );
      ref.read(moduleProgressTickProvider.notifier).state++;

      // ✨ 2. Evaluate Quiz Achievements locally!
      final percentageScore = (_score / _questions.length) * 100;
      final isPerfect = _score == _questions.length;

      if (percentageScore >= 60.0) {
        unawaited(ref.read(achievementEngineProvider).recordQuizPass(
              widget.quizId,
              perfectScore: isPerfect,
            ));
      }

      // ✨ FIX: Push to the newly defined, collision-free route
      context.push('/quiz-result', extra: {
        'score': _score,
        'total': _questions.length,
        'xpEarned': xpEarned,
        'quizId': widget.quizId,
        'questions': _questions,
        'studentAnswers': _studentAnswers,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = ref.watch(themeProvider);
    final themeHighlight = ThemeHelper.getActiveHighlight(activeTheme);
    final isDark = !ThemeHelper.isLightTheme(activeTheme);

    if (_loading) {
      // Use a Stack so the background animation shows during loading too.
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const Positioned.fill(child: LanguageAlphabetBackground()),
            Center(
              child: CircularProgressIndicator(color: themeHighlight),
            ),
          ],
        ),
      );
    }

    // Clean empty state: the dashboard has not published a quiz for this module
    // yet (or the pack hasn't reached this device). Never show demo questions.
    if (_questions.isEmpty) {
      return Stack(
        children: [
          const Positioned.fill(child: LanguageAlphabetBackground()),
          MitraScaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('📝', style: TextStyle(fontSize: 56)),
                    SizedBox(height: 16),
                    Text(
                      'No quiz yet',
                      style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: MitraColors.textPrimary),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "This module's quiz will appear here once it is released.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 14,
                          color: MitraColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final q = _questions[_current];
    final progress = (_current + 1) / _questions.length;

    final isCorrect = _selected == q.correctAnswerIndex;

    // Quiz screens live outside StudentShell so they don't inherit its
    // LanguageAlphabetBackground. We add it here as the first Stack layer
    // so the background animation is consistent with the rest of the app.
    return Stack(
      children: [
        const Positioned.fill(child: LanguageAlphabetBackground()),
        MitraScaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Question ${_current + 1}/${_questions.length}',
              style: const TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white),
            ),
            leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => context.pop()),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(
                MitraSpacing.lg, 0, MitraSpacing.lg, MitraSpacing.lg),
            child: Column(
              children: [
                // ── Progress bar ──────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(MitraRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        MitraColors.bgSurface.withValues(alpha: 0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(themeHighlight),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Question dot indicators ───────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_questions.length, (i) {
                    Color dotColor;
                    if (i < _current) {
                      // Already answered
                      final wasCorrect = _studentAnswers[i] ==
                          _questions[i].correctAnswerIndex;
                      dotColor = wasCorrect
                          ? MitraColors.emerald
                          : MitraColors.crimson;
                    } else if (i == _current) {
                      dotColor = themeHighlight;
                    } else {
                      dotColor = Colors.white.withValues(alpha: 0.2);
                    }
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _current ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: MitraSpacing.lg),

                // ── Scrollable content ────────────────────
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            // Question card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(MitraSpacing.xl),
                              decoration: BoxDecoration(
                                color:
                                    MitraColors.bgCard.withValues(alpha: 0.8),
                                borderRadius:
                                    BorderRadius.circular(MitraRadius.lg),
                                border: Border.all(
                                    color: MitraColors.border
                                        .withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                q.questionText,
                                style: const TextStyle(
                                    fontFamily: 'Baloo2',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    color: Colors.white,
                                    height: 1.4),
                              ),
                            ),

                            const SizedBox(height: MitraSpacing.lg),

                            // ── Options ───────────────────────
                            ...List.generate(q.options.length, (i) {
                              final isSelected = _selected == i;
                              final isCorrect = i == q.correctAnswerIndex;
                              final showResult = _answered;

                              Color borderColor;
                              Color bgColor;
                              Color textColor;
                              Color letterBg;
                              Color letterText;

                              if (!showResult) {
                                borderColor = isSelected
                                    ? themeHighlight
                                    : MitraColors.border.withValues(alpha: 0.2);
                                bgColor = isSelected
                                    ? themeHighlight.withValues(alpha: 0.15)
                                    : MitraColors.bgCard.withValues(alpha: 0.5);
                                textColor = isSelected
                                    ? themeHighlight
                                    : (isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1A2E));
                                letterBg = isSelected
                                    ? themeHighlight
                                    : MitraColors.bgSurface;
                                letterText = isSelected
                                    ? Colors.black
                                    : (isDark
                                        ? Colors.white70
                                        : const Color(0xB31A1A2E));
                              } else if (isSelected && isCorrect) {
                                borderColor = MitraColors.emerald;
                                bgColor =
                                    MitraColors.emerald.withValues(alpha: 0.15);
                                textColor = MitraColors.emerald;
                                letterBg = MitraColors.emerald;
                                letterText = Colors.white;
                              } else if (isSelected && !isCorrect) {
                                borderColor = MitraColors.crimson;
                                bgColor =
                                    MitraColors.crimson.withValues(alpha: 0.12);
                                textColor = MitraColors.crimson;
                                letterBg = MitraColors.crimson;
                                letterText = Colors.white;
                              } else {
                                borderColor =
                                    MitraColors.border.withValues(alpha: 0.1);
                                bgColor =
                                    MitraColors.bgCard.withValues(alpha: 0.2);
                                textColor = Colors.white.withValues(alpha: 0.3);
                                letterBg = Colors.white.withValues(alpha: 0.05);
                                letterText =
                                    Colors.white.withValues(alpha: 0.3);
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: GestureDetector(
                                  onTap: () => _selectAnswer(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: double.infinity,
                                    padding:
                                        const EdgeInsets.all(MitraSpacing.lg),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius:
                                          BorderRadius.circular(MitraRadius.md),
                                      border: Border.all(
                                          color: borderColor,
                                          width: showResult &&
                                                  (isCorrect || isSelected)
                                              ? 1.5
                                              : 1),
                                    ),
                                    child: Row(children: [
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: letterBg,
                                          border: Border.all(
                                              color: borderColor.withValues(
                                                  alpha: 0.5)),
                                        ),
                                        alignment: Alignment.center,
                                        child: showResult &&
                                                isSelected &&
                                                isCorrect
                                            ? const Icon(Icons.check,
                                                size: 14, color: Colors.white)
                                            : showResult &&
                                                    isSelected &&
                                                    !isCorrect
                                                ? const Icon(Icons.close,
                                                    size: 14,
                                                    color: Colors.white)
                                                : Text(
                                                    ['A', 'B', 'C', 'D'][i],
                                                    style: TextStyle(
                                                        fontFamily: 'SpaceMono',
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                        color: letterText),
                                                  ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          q.options[i],
                                          style: TextStyle(
                                            fontFamily: 'Mukta',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 15,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),

                      // ✨ NEW: Dynamic Centered Pop-up Area
                      if (_answered)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(top: 8.0, bottom: 8.0),
                            child: isCorrect
                                ? Container(
                                    width: double.infinity,
                                    padding:
                                        const EdgeInsets.all(MitraSpacing.xl),
                                    decoration: BoxDecoration(
                                      color: MitraColors.emerald
                                          .withValues(alpha: 0.10),
                                      borderRadius:
                                          BorderRadius.circular(MitraRadius.lg),
                                      border: Border.all(
                                          color: MitraColors.emerald
                                              .withValues(alpha: 0.30),
                                          width: 2),
                                    ),
                                    // FittedBox scales the huge font down beautifully if space is tight!
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.center,
                                      child: SizedBox(
                                        width: 350,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.check_circle,
                                                color: MitraColors.emerald,
                                                size: 64),
                                            const SizedBox(height: 16),
                                            if (q.explanation != null)
                                              Text(
                                                q.explanation!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontFamily: 'Mukta',
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w600,
                                                  color: MitraColors.emerald,
                                                  height: 1.3,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: double.infinity,
                                    padding:
                                        const EdgeInsets.all(MitraSpacing.xl),
                                    decoration: BoxDecoration(
                                      color: MitraColors.crimson
                                          .withValues(alpha: 0.10),
                                      borderRadius:
                                          BorderRadius.circular(MitraRadius.lg),
                                      border: Border.all(
                                          color: MitraColors.crimson
                                              .withValues(alpha: 0.30),
                                          width: 2),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('⚠️',
                                              style: TextStyle(fontSize: 80)),
                                          SizedBox(height: 16),
                                          Text(
                                            'WRONG ANSWER!',
                                            style: TextStyle(
                                              fontFamily: 'Baloo2',
                                              fontSize: 42,
                                              fontWeight: FontWeight.w900,
                                              color: MitraColors.crimson,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: MitraSpacing.md),

                // ── Next / Submit button ──────────────────
                if (_answered)
                  GestureDetector(
                    onTap: _canAdvance ? _next : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _canAdvance
                            ? themeHighlight
                            : MitraColors.bgSurface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _canAdvance
                            ? (_current < _questions.length - 1
                                ? 'Next Question →'
                                : 'See Results →')
                            : 'Read explanation to continue...',
                        style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: _canAdvance
                                ? Colors.black
                                : (isDark
                                    ? Colors.white54
                                    : const Color(0x8A1A1A2E))),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: MitraColors.bgSurface.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(MitraRadius.pill),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Select an answer',
                      style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDark
                              ? Colors.white38
                              : const Color(0x991A1A2E)),
                    ),
                  ),
              ], // ✨ FIX: Closes the Column children
            ), // ✨ FIX: Closes the Column
          ), // ✨ FIX: Closes the Padding
        ), // ✨ FIX: Closes the MitraScaffold

        // ✨ Emergency Flash Overlay
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _flashCtrl,
            builder: (context, child) {
              return Container(
                color: _flashColor.value,
              );
            },
          ),
        ),
      ],
    );
  }
}
