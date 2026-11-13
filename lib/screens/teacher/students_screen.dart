import 'package:flutter/material.dart';
import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/colors.dart';
import '../../services/api_service.dart';

final studentsProvider = FutureProvider<List<dynamic>>((ref) async {
  final res = await DashboardAPI.classroom({'type': 'students'});
  return res.data['students'] as List<dynamic>? ?? [];
});

class StudentsScreen extends ConsumerWidget {
  const StudentsScreen({super.key});

  static const _mockStudents = [
    {
      'name': 'Rahul Sharma',
      'class': 'Class 9',
      'xp': 980,
      'streak': 8,
      'emoji': '🎒'
    },
    {
      'name': 'Priya Mehta',
      'class': 'Class 9',
      'xp': 860,
      'streak': 6,
      'emoji': '🌟'
    },
    {
      'name': 'Arjun Kumar',
      'class': 'Class 9',
      'xp': 720,
      'streak': 5,
      'emoji': '🔬'
    },
    {
      'name': 'Divya Reddy',
      'class': 'Class 9',
      'xp': 680,
      'streak': 4,
      'emoji': '📚'
    },
    {
      'name': 'Kiran Patil',
      'class': 'Class 9',
      'xp': 540,
      'streak': 3,
      'emoji': '🏆'
    },
    {
      'name': 'Sneha Joshi',
      'class': 'Class 9',
      'xp': 410,
      'streak': 2,
      'emoji': '🌍'
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
              Text('👥', style: TextStyle(fontSize: 24)),
              SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr(ref, 'teacher_students', 'Students'),
                    style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: MitraColors.textPrimary)),
                Text(context.tr(ref, 'teacher_your_classroom_roster', 'Your classroom roster'),
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
              itemCount: _mockStudents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final s = _mockStudents[i];
                return Container(
                  padding: const EdgeInsets.all(MitraSpacing.md),
                  decoration: BoxDecoration(
                    color: MitraColors.bgCard,
                    borderRadius: BorderRadius.circular(MitraRadius.md),
                    border: Border.all(color: MitraColors.border),
                  ),
                  child: Row(children: [
                    Text(s['emoji'] as String,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(s['name'] as String,
                              style: const TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: MitraColors.textPrimary)),
                          Text('${s['class']} · 🔥 ${s['streak']} streak',
                              style: const TextStyle(
                                  fontFamily: 'Mukta',
                                  fontSize: 12,
                                  color: MitraColors.textMuted)),
                        ])),
                    Text('${s['xp']} XP',
                        style: const TextStyle(
                            fontFamily: 'SpaceMono',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: MitraColors.gold)),
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
