import 'package:flutter/material.dart';
import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/colors.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

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
              Text('📊', style: TextStyle(fontSize: 24)),
              SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr(ref, 'teacher_analytics', 'Analytics'),
                    style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: MitraColors.textPrimary)),
                Text(context.tr(ref, 'teacher_classroom_performance_insigh', 'Classroom performance insights'),
                    style: TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 12,
                        color: MitraColors.textMuted)),
              ]),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(MitraSpacing.lg),
              children: [
                _AnalyticsCard(
                    title: context.tr(ref, 'teacher_class_average', 'Class Average'),
                    value: '74%',
                    subtitle: context.tr(ref, 'teacher_3_from_last_week', '+3% from last week'),
                    positive: true),
                SizedBox(height: 12),
                _AnalyticsCard(
                    title: context.tr(ref, 'teacher_quiz_completion_rate', 'Quiz Completion Rate'),
                    value: '63%',
                    subtitle: context.tr(ref, 'teacher_target_80', 'Target: 80%'),
                    positive: false),
                SizedBox(height: 12),
                _AnalyticsCard(
                    title: context.tr(ref, 'teacher_ar_sessions_this_week', 'AR Sessions This Week'),
                    value: '128',
                    subtitle: context.tr(ref, 'teacher_22_from_last_week', '+22% from last week'),
                    positive: true),
                SizedBox(height: 12),
                _AnalyticsCard(
                    title: context.tr(ref, 'teacher_students_active_today', 'Students Active Today'),
                    value: '31/42',
                    subtitle: context.tr(ref, 'teacher_74_attendance', '74% attendance'),
                    positive: true),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title, value, subtitle;
  final bool positive;
  const _AnalyticsCard(
      {required this.title,
      required this.value,
      required this.subtitle,
      required this.positive});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(MitraSpacing.lg),
        decoration: BoxDecoration(
            color: MitraColors.bgCard,
            borderRadius: BorderRadius.circular(MitraRadius.md),
            border: Border.all(color: MitraColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 12,
                  color: MitraColors.textMuted,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  color: MitraColors.textPrimary)),
          Text(subtitle,
              style: TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 12,
                  color: positive ? MitraColors.emerald : MitraColors.crimson)),
        ]),
      );
}
