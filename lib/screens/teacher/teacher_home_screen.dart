import 'package:flutter/material.dart';
import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/colors.dart';
import '../../stores/auth_store.dart';

class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: MitraColors.gradientTeacher),
                ),
                padding: const EdgeInsets.all(MitraSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr(ref, 'teacher_teacher_dashboard', 'Teacher Dashboard'),
                              style: TextStyle(
                                  fontFamily: 'Mukta',
                                  fontSize: 12,
                                  color: MitraColors.textMuted)),
                          Text(user?.fullName ?? context.tr(ref, 'auth_teacher', 'Teacher'),
                              style: const TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: MitraColors.textPrimary)),
                          Text(
                              '${user?.assignedState ?? ''} · ${user?.assignedDistrict ?? ''}',
                              style: const TextStyle(
                                  fontFamily: 'Mukta',
                                  fontSize: 12,
                                  color: MitraColors.textMuted)),
                        ]),
                    Text(user?.avatarEmoji ?? '👩‍🏫',
                        style: const TextStyle(fontSize: 36)),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(MitraSpacing.lg),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: _MetricCard(
                            emoji: '👥', label: context.tr(ref, 'teacher_students', 'Students'), value: '42')),
                    SizedBox(width: 12),
                    Expanded(
                        child: _MetricCard(
                            emoji: '📊', label: context.tr(ref, 'teacher_avg_score', 'Avg Score'), value: '74%')),
                  ]),
                  SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _MetricCard(
                            emoji: '📝', label: context.tr(ref, 'home_quizzes', 'Quizzes'), value: '8')),
                    SizedBox(width: 12),
                    Expanded(
                        child: _MetricCard(
                            emoji: '🏆', label: context.tr(ref, 'teacher_completion', 'Completion'), value: '63%')),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String emoji, label, value;
  const _MetricCard(
      {required this.emoji, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(MitraSpacing.lg),
        decoration: BoxDecoration(
          color: MitraColors.bgCard,
          borderRadius: BorderRadius.circular(MitraRadius.md),
          border: Border.all(color: const Color(0x330DC389)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  color: MitraColors.emerald)),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 12,
                  color: MitraColors.textMuted)),
        ]),
      );
}
