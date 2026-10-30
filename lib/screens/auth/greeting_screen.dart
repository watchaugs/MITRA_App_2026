import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../stores/auth_store.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../constants/colors.dart';
import 'package:lottie/lottie.dart'; // ✨ Added Lottie Engine

class GreetingScreen extends ConsumerStatefulWidget {
  final String nextRoute;

  const GreetingScreen({super.key, required this.nextRoute});

  @override
  ConsumerState<GreetingScreen> createState() => _GreetingScreenState();
}

class _GreetingScreenState extends ConsumerState<GreetingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Entrance & Typing Animations
  late Animation<double> _namasteFade;
  late Animation<double> _namasteScale;
  late Animation<int> _nameTyping;

  // Unified Continuous Exit Sweeping/Collapsing Animation
  late Animation<double> _exitScale;
  late Animation<Alignment> _exitAlignment;
  late Animation<double> _exitFade;

  String _displayName = '';

  @override
  void initState() {
    super.initState();

    final user = ref.read(currentUserProvider);
    _displayName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : 'Student';

    // 3-second explicit animation timeline
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // --- ENTRANCE PHASE (0.0 -> 0.20) ---
    _namasteFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.20, curve: Curves.easeIn)),
    );
    _namasteScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.20, curve: Curves.elasticOut)),
    );

    // --- TYPING PHASE (0.22 -> 0.65) ---
    _nameTyping = StepTween(begin: 0, end: _displayName.length).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.22, 0.65, curve: Curves.linear)),
    );

    // --- CONTINUOUS SWEEPING EXIT PHASE (0.80 -> 1.0) ---
    // Seamlessly transitions from Center to Top-Left target coordinates
    _exitAlignment = AlignmentTween(
      begin: Alignment.center,
      end: const Alignment(
          -0.85, -0.82), // Matches home screen header text positioning
    ).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.80, 1.0, curve: Curves.easeInOutCubic)),
    );

    // Collapses size smoothly down to blend into the student text header dimensions
    _exitScale = Tween<double>(begin: 1.0, end: 0.42).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.80, 1.0, curve: Curves.easeInOutCubic)),
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.95, 1.0, curve: Curves.easeIn)),
    );

    // Run animation and trigger standard route handover
    _controller.forward().then((_) {
      if (mounted) context.go(widget.nextRoute);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double baseFontSize = screenWidth > 600 ? 26.0 : 20.0;

    return MitraScaffold(
      // ✨ 1. Force the Stack to fill the entire screen
      body: SizedBox.expand(
        child: Stack(
          children: [
            // 1. The sweeping text animation
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                String typedName = _displayName.substring(0, _nameTyping.value);

                return Align(
                  alignment: _exitAlignment.value,
                  child: FractionallySizedBox(
                    widthFactor: 0.85,
                    child: FadeTransition(
                      opacity: _exitFade,
                      child: ScaleTransition(
                        scale: _exitScale,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Namaste Text (Regular Font Weight / Zoom-In Pop Entrance)
                            FadeTransition(
                              opacity: _namasteFade,
                              child: ScaleTransition(
                                scale: _namasteScale,
                                child: Text(
                                  'NAMASTE 🙏🏽',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Mukta',
                                    fontSize: baseFontSize,
                                    fontWeight:
                                        FontWeight.w400, // Regular font weight
                                    color: Colors.white70,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Dynamic Character Typed Name Display (Bold & 2x Base Scale)
                            Text(
                              typedName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontSize: baseFontSize *
                                    2.0, // 2x base height constraint
                                fontWeight: FontWeight.w800,
                                color: MitraColors.textPrimary,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // ✨ 2. The waving hands animation anchored directly to the bottom
            Positioned(
              bottom: 0, // Sticks exactly to the bottom edge of the screen
              left:
                  0, // Setting both left and right to 0 centers the asset horizontally
              right: 0,
              child: Lottie.asset(
                'assets/lotties/waving_hands.json',
                repeat: false,
                width: 312.5, // ✨ Increased size by 25% (250 * 1.25)
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
