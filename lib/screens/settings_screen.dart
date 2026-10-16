import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/theme_provider.dart';
import '../widgets/mitra_glass_card.dart';
import '../widgets/mitra_scaffold.dart';
import '../../constants/colors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(themeProvider);

    return MitraScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'App Settings',
          style: TextStyle(
              fontFamily: 'Baloo2',
              color: ThemeHelper.textPrimary(activeTheme),
              fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: ThemeHelper.textPrimary(activeTheme)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Appearance ────────────────────────────
            const Text(
              'Appearance',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose your preferred visual theme. This will apply to all screens instantly.',
              style: TextStyle(fontFamily: 'Mukta', color: Colors.white70),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView.separated(
                itemCount: ThemeHelper.selectableThemes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final themeOption = ThemeHelper.selectableThemes[index];
                  return MitraGlassCard(
                    title: ThemeHelper.getThemeName(themeOption),
                    isSelected: activeTheme == themeOption,
                    activeColor: MitraColors.saffron,
                    onTap: () =>
                        ref.read(themeProvider.notifier).setTheme(themeOption),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // ── Class ─────────────────────────────────
            const Text(
              'Class',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your class is locked for 90 days after selection.',
              style: TextStyle(fontFamily: 'Mukta', color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const _ClassChangeTile(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Class Change Tile
// ════════════════════════════════════════════════════════════

class _ClassChangeTile extends StatefulWidget {
  const _ClassChangeTile();

  @override
  State<_ClassChangeTile> createState() => _ClassChangeTileState();
}

class _ClassChangeTileState extends State<_ClassChangeTile> {
  bool _locked = true;
  bool _loading = true;
  String _daysLeft = '';

  @override
  void initState() {
    super.initState();
    _checkLock();
  }

  Future<void> _checkLock() async {
    final prefs = await SharedPreferences.getInstance();
    final lockedAtStr = prefs.getString('classLockedAt');

    if (!mounted) return;

    if (lockedAtStr == null) {
      setState(() {
        _locked = false;
        _loading = false;
      });
      return;
    }

    final lockedAt = DateTime.tryParse(lockedAtStr);
    if (lockedAt == null) {
      setState(() {
        _locked = false;
        _loading = false;
      });
      return;
    }

    final unlockDate = lockedAt.add(const Duration(days: 90));
    final now = DateTime.now();

    if (now.isAfter(unlockDate)) {
      setState(() {
        _locked = false;
        _loading = false;
      });
    } else {
      final remaining = unlockDate.difference(now).inDays + 1;
      setState(() {
        _locked = true;
        _loading = false;
        _daysLeft = '$remaining days remaining';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show nothing while checking — avoids flicker
    if (_loading) {
      return Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(MitraRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              color: MitraColors.saffron, strokeWidth: 2),
        ),
      );
    }

    return GestureDetector(
      onTap: _locked ? null : () => context.go('/setup/class'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _locked
              ? Colors.white.withValues(alpha: 0.04)
              : MitraColors.saffron.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(MitraRadius.md),
          border: Border.all(
            color: _locked
                ? Colors.white.withValues(alpha: 0.12)
                : MitraColors.saffron.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _locked ? Icons.lock_outline : Icons.edit_outlined,
              color: _locked ? Colors.white38 : MitraColors.saffron,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Change Class',
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: _locked ? Colors.white38 : Colors.white,
                    ),
                  ),
                  Text(
                    _locked
                        ? '🔒  Locked · $_daysLeft'
                        : 'Tap to select a new class',
                    style: TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 12,
                      color: _locked ? Colors.white30 : MitraColors.saffron,
                    ),
                  ),
                ],
              ),
            ),
            if (!_locked)
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: MitraColors.saffron),
          ],
        ),
      ),
    );
  }
}
