import 'package:flutter/material.dart';
import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/colors.dart';

class AssignScreen extends ConsumerWidget {
  const AssignScreen({super.key});

  static const _content = [
    {
      'emoji': '🔬',
      'title': 'Cell Division AR',
      'type': 'AR Module',
      'subject': 'Science'
    },
    {
      'emoji': '📐',
      'title': 'Algebra Basics Quiz',
      'type': 'Quiz',
      'subject': 'Maths'
    },
    {
      'emoji': '🌍',
      'title': 'Solar System 3D',
      'type': 'AR Module',
      'subject': 'Geography'
    },
    {
      'emoji': '🏛️',
      'title': 'Ancient India Timeline',
      'type': 'AR Module',
      'subject': 'History'
    },
    {
      'emoji': '⚗️',
      'title': 'Chemical Reactions Quiz',
      'type': 'Quiz',
      'subject': 'Science'
    },
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Container(
            color: MitraColors.bgCard,
            padding: const EdgeInsets.all(MitraSpacing.lg),
            child: Row(children: [
              Text('📚', style: TextStyle(fontSize: 24)),
              SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr(ref, 'teacher_assign_content', 'Assign Content'),
                    style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: MitraColors.textPrimary)),
                Text(context.tr(ref, 'teacher_push_lessons_quizzes_to_your', 'Push lessons & quizzes to your class'),
                    style: TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 12,
                        color: MitraColors.textMuted)),
              ]),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(MitraSpacing.lg),
              itemCount: _content.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final c = _content[i];
                return Container(
                  padding: const EdgeInsets.all(MitraSpacing.md),
                  decoration: BoxDecoration(
                      color: MitraColors.bgCard,
                      borderRadius: BorderRadius.circular(MitraRadius.md),
                      border: Border.all(color: MitraColors.border)),
                  child: Row(children: [
                    Text(c['emoji'] as String,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(c['title'] as String,
                              style: const TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: MitraColors.textPrimary)),
                          Text('${c['type']} · ${c['subject']}',
                              style: const TextStyle(
                                  fontFamily: 'Mukta',
                                  fontSize: 12,
                                  color: MitraColors.textMuted)),
                        ])),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MitraColors.emerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(MitraRadius.pill)),
                        textStyle: const TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                      onPressed: () {},
                      child: Text(context.tr(ref, 'teacher_assign', 'Assign')),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
