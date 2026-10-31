// ═══════════════════════════════════════════════════════
// SCREEN S-03: Login — WhatsApp OTP Authentication
// Mirrors app/login.tsx from Expo project
// ═══════════════════════════════════════════════════════

import 'dart:async'; // 🛠️ Added for Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../../constants/colors.dart';
import '../../stores/auth_store.dart';
import '../../models/user.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../theme/theme_provider.dart';
import '../../services/api_service.dart';
//import '../../theme/theme_provider.dart';

enum _LoginStep { phone, otp }

enum _Role { student, teacher }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _storage = const FlutterSecureStorage();
  final _phoneCtrl = TextEditingController();
  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpFocuses = List.generate(6, (_) => FocusNode());

  _LoginStep _step = _LoginStep.phone;
  _Role _role = _Role.student;
  bool _loading = false;
  int _resendTimer = 0;
  Timer? _timer;
  String _verificationId = '';

  // Countdown ticker
  void _startResendTimer() {
    _timer?.cancel();
    int countdown = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendTimer = countdown--);
      if (countdown < 0) timer.cancel();
    });
  }

  // ═══════════════════════════════════════════════════════
  // ☁️ REAL FIREBASE CLOUD AUTHENTICATION
  // ═══════════════════════════════════════════════════════

  Future<void> _sendOTP() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      _showError(
          'Invalid Number', 'Please enter a valid 10-digit mobile number.');
      return;
    }

    setState(() => _loading = true);

    try {
      // Production: real app verification (Play Integrity / reCAPTCHA) stays ON.
      // (Was appVerificationDisabledForTesting: true — a testing-only flag that
      //  must never ship, or real OTP verification is bypassed.)
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$phone',
        verificationCompleted: (PhoneAuthCredential credential) async {
          final userCred =
              await FirebaseAuth.instance.signInWithCredential(credential);
          await _saveUserAndNavigate(userCred.user!);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _loading = false);
          _showError('Verification Failed', e.message ?? 'Unknown error');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _loading = false;
            _step = _LoginStep.otp;
          });
          _startResendTimer();
          Future.delayed(const Duration(milliseconds: 300),
              () => _otpFocuses[0].requestFocus());
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _loading = false);
      _showError('Error', 'Failed to trigger SMS. Please try again.');
    }
  }

  bool _isGoogleInitialized = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);

    try {
      debugPrint("🚨 STEP 1: Starting Google Sign In...");
      final googleSignIn = GoogleSignIn.instance;

      if (!_isGoogleInitialized) {
        await googleSignIn.initialize();
        _isGoogleInitialized = true;
      }

      final GoogleSignInAccount googleUser = await googleSignIn.authenticate();

      debugPrint("🚨 STEP 2: Google Account Selected");
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      debugPrint("🚨 STEP 3: Creating Firebase Credential...");
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      debugPrint("🚨 STEP 4: Sending Credential to Firebase...");
      final UserCredential userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      debugPrint("🚨 STEP 5: Firebase Auth Success! Saving to Database...");
      await _saveUserAndNavigate(userCred.user!);

      debugPrint("🚨 STEP 6: Routing to Dashboard!");
    } catch (e) {
      setState(() => _loading = false);
      debugPrint("🚨 GOOGLE SIGN-IN FATAL ERROR: $e");
      _showError('Google Login Failed',
          'Could not sign in with Google. Please try again.');
    }
  }

  Future<void> _verifyOTP() async {
    final code = _otpCtrls.map((c) => c.text).join();
    if (code.length != 6) {
      _showError('Incomplete OTP', 'Please enter all 6 digits.');
      return;
    }

    setState(() => _loading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );

      final UserCredential userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _saveUserAndNavigate(userCred.user!);
    } catch (e) {
      setState(() => _loading = false);
      _showError('Wrong OTP', 'The OTP is incorrect or expired.');
    }
  }

  // ── ☁️ FIRESTORE DATABASE SAVER ──
  Future<void> _saveUserAndNavigate(User firebaseUser) async {
    try {
      // 1. Save the new user directly into your SPECIFIC '(default)' Database Instance
      await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: '(default)',
        // Security: the app only ever self-provisions a STUDENT. A teacher role is
        // granted by the backend after verification (Firestore rules reject a
        // client-written 'teacher'), so we never write the toggle's value here.
      ).collection('app_users').doc(firebaseUser.uid).set({
        'id': firebaseUser.uid,
        'phone': firebaseUser.phoneNumber ?? '',
        'email': firebaseUser.email ?? '',
        // Do NOT write a placeholder name here. A returning user already has
        // full_name from onboarding; overwriting it (even into a different field)
        // and caching the placeholder makes the name revert to "App student" on
        // relaunch. Only set a name if Firebase actually gives us a real one.
        if ((firebaseUser.displayName ?? '').trim().isNotEmpty)
          'full_name': firebaseUser.displayName!.trim(),
        'role': 'student',
        'last_login': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Build the interim user from whatever REAL data we have. Never inject a
      // placeholder like "App student" — the auth store will fetch the full
      // profile (with the real full_name) from Firestore right after, and
      // caching a placeholder here is what made the name revert on relaunch.
      // Prefer an already-known name from the existing session if present.
      final existing = ref.read(authProvider).user;
      final knownName = (firebaseUser.displayName?.trim().isNotEmpty ?? false)
          ? firebaseUser.displayName!.trim()
          : (existing?.fullName.trim().isNotEmpty ?? false)
              ? existing!.fullName.trim()
              : '';
      final consumerUser = MitraUser(
        id: firebaseUser.uid,
        fullName: knownName, // empty until Firestore fills it; no placeholder
        phone: firebaseUser.phoneNumber ?? '',
        role: _role.name,
      );

      ref.read(authProvider.notifier).setUser(consumerUser);
      await _storage.write(key: 'mitra_consumer_logged_in', value: 'true');
      await _storage.write(key: 'mitra_consumer_role', value: _role.name);

      // ── Get backend JWT by exchanging the Firebase ID token ──────
      // The student is already signed in with real Firebase Phone OTP above.
      // We hand that verified identity to the backend, which mints its own JWTs.
      try {
        final firebaseIdToken = await firebaseUser.getIdToken();

        final plainDio = Dio(BaseOptions(
          baseUrl: ApiService.instance.dio.options.baseUrl,
          headers: {
            'Content-Type': 'application/json',
            'Origin': 'https://watchaugs-mitra.web.app',
          },
        ));
        final backendRes = await plainDio.post(
          '/api/auth/firebase',
          data: {
            'id_token': firebaseIdToken,
            'role': _role.name,
          },
        );
        final accessToken = backendRes.data['access_token'] as String?;
        final refreshToken = backendRes.data['refresh_token'] as String?;
        if (accessToken != null) {
          await _storage.write(key: 'mitra_access_token', value: accessToken);
          debugPrint('✅ Backend JWT stored');
        }
        if (refreshToken != null) {
          await _storage.write(key: 'mitra_refresh_token', value: refreshToken);
        }
      } catch (e) {
        debugPrint('⚠️ Backend JWT exchange failed: $e');
      }

      // ✨ INJECTED CODE: Lock the onboarding door permanently for returning users
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboardingComplete', true);

      if (!mounted) return;

      // 🚨 BUG FIX: Route to the proper Home Screen instead of the Splash Screen
      // Gate behind consent screen (DPDPA) on first login
      final consentGiven = prefs.getBool('consentGiven') ?? false;
      final String homeRoute =
          _role == _Role.teacher ? '/teacher/home' : '/student/home';

      // New users: determine LOCATION first → that sets the regional language →
      // then the language picker → then consent (shown in the chosen language).
      // Returning users who already consented skip straight to the greeting.
      final onboardingDone = prefs.getBool('onboardingComplete') ?? false;
      if (consentGiven) {
        context.go('/greeting?next=$homeRoute');
      } else if (!onboardingDone) {
        // location → language → consent → home
        context.go('/location');
      } else {
        // Location already captured earlier; go to language then consent.
        // State isn't known in this scope — the language screen falls back to
        // Hindi + English, and the main onboarding path (/location) sets it.
        context.go(
            '/language?next=${Uri.encodeComponent('/consent?next=$homeRoute')}');
      }
    } catch (e) {
      debugPrint("🚨 FIRESTORE ERROR: $e");
      _showError('Database Error', 'Could not save profile to cloud.');
      setState(() => _loading = false);
    }
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MitraColors.bgCard,
        title:
            Text(title, style: const TextStyle(color: MitraColors.textPrimary)),
        content: Text(message,
            style: const TextStyle(color: MitraColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK',
                  style: TextStyle(color: MitraColors.saffron))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocuses) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✨ RESTORED: Fetching the dynamic color safely inside the UI!
    final activeTheme = ref.watch(themeProvider);
    final activeHighlight = ThemeHelper.getActiveHighlight(activeTheme);

    return MitraScaffold(
      body: Column(
        children: [
          // ── Top hero art (Theme-Blended) ────────────────────────────
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              // ✨ THE MAGIC: Smoothly fades from Logo Navy into the current Theme Background!
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0F1B3E), // Matches the logo's top edge
                  Theme.of(context)
                      .scaffoldBackgroundColor, // Fades seamlessly into the active theme // Fades seamlessly into the active theme
                ],
                stops: const [
                  0.6,
                  1.0
                ], // Keeps it mostly navy, fading only at the very bottom
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/logo_horizontal_1800x500_navy.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Welcome to MITRA',
                            style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                color: Colors.white),
                          ),
                          Text(
                            'Sign in to continue learning',
                            style: TextStyle(
                                fontFamily: 'Mukta',
                                fontSize: 13,
                                color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Form area ───────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(MitraSpacing.lg),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Role selector
                  Row(
                    children: _Role.values
                        .map((r) => Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                    right: r == _Role.student ? 4 : 0,
                                    left: r == _Role.teacher ? 4 : 0),
                                child: GestureDetector(
                                  onTap: () => setState(() => _role = r),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _role == r
                                          ? MitraColors.saffron
                                              .withValues(alpha: 0.1)
                                          : MitraColors.bgCard,
                                      borderRadius:
                                          BorderRadius.circular(MitraRadius.sm),
                                      border: Border.all(
                                        color: _role == r
                                            ? MitraColors.saffron
                                            : MitraColors.border,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                            r == _Role.student ? '🎒' : '👩‍🏫',
                                            style:
                                                const TextStyle(fontSize: 18)),
                                        const SizedBox(width: 6),
                                        Text(
                                          r == _Role.student
                                              ? 'Student'
                                              : 'Teacher',
                                          style: TextStyle(
                                            fontFamily: 'Mukta',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                            color: _role == r
                                                ? MitraColors.saffron
                                                : MitraColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: MitraSpacing.lg),

                  // ✨ We hand the color down to the methods!
                  if (_step == _LoginStep.phone)
                    ..._buildPhoneStep(activeHighlight) // ✨ Passing it down
                  else
                    ..._buildOTPStep(activeHighlight), // ✨ Passing it down
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPhoneStep(Color activeHighlight) => [
        const Text('MOBILE NUMBER',
            style: TextStyle(
                fontFamily: 'Mukta',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: MitraColors.textMuted,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: MitraColors.bgCard,
            borderRadius: BorderRadius.circular(MitraRadius.sm),
            border: Border.all(color: MitraColors.border),
          ),
          child: Row(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(
                  children: [
                    const Text('🇮🇳', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    const Text('+91',
                        style: TextStyle(
                            fontFamily: 'SpaceMono',
                            fontSize: 14,
                            color: MitraColors.textPrimary)),
                    const SizedBox(width: 8),
                    Container(width: 1, height: 20, color: MitraColors.border),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      fontFamily: 'SpaceMono',
                      fontSize: 16,
                      color: MitraColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '10-digit number',
                    hintStyle: TextStyle(color: MitraColors.textMuted),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MitraSpacing.lg),
        _GradientButton(
          label: 'Send OTP →', // Generalized for future SMS integration
          loading: _loading,
          color: activeHighlight,
          onTap: _sendOTP,
        ),

        const SizedBox(height: 24), // Spacing before the divider

        // --- VISUAL "OR" DIVIDER ---
        const Row(
          children: [
            Expanded(child: Divider(color: MitraColors.border)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(
                  color: MitraColors.textMuted,
                  fontFamily: 'Mukta',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(child: Divider(color: MitraColors.border)),
          ],
        ),

        const SizedBox(height: 24), // Spacing after the divider

        // --- GOOGLE SIGN-IN BUTTON ---
        OutlinedButton.icon(
          onPressed: _loading ? null : _signInWithGoogle,
          icon: Image.network(
            'https://img.icons8.com/color/48/000000/google-logo.png',
            height: 24,
          ),
          label: const Text(
            'Continue with Google',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: MitraColors.textPrimary),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            side: const BorderSide(color: MitraColors.border, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
            ),
          ),
        ),
      ];

  List<Widget> _buildOTPStep(Color activeHighlight) => [
        Container(
          padding: const EdgeInsets.all(MitraSpacing.md),
          decoration: BoxDecoration(
            color: MitraColors.emerald.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(MitraRadius.sm),
            border:
                Border.all(color: MitraColors.emerald.withValues(alpha: 0.3)),
          ),
          child: Text(
            '💬  OTP sent to +91 ${_phoneCtrl.text.substring(0, 3)}XXXXXXX',
            style: const TextStyle(
                fontFamily: 'Mukta', fontSize: 13, color: MitraColors.emerald),
          ),
        ),
        const SizedBox(height: MitraSpacing.lg),

        // OTP boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
              6,
              (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 46,
                      height: 56,
                      child: TextField(
                        controller: _otpCtrls[i],
                        focusNode: _otpFocuses[i],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: const TextStyle(
                            fontFamily: 'SpaceMono',
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            color: MitraColors.textPrimary),
                        decoration: InputDecoration(
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(MitraRadius.xs),
                            borderSide: const BorderSide(
                                color: MitraColors.border, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(MitraRadius.xs),
                            borderSide: const BorderSide(
                                color: MitraColors.saffron, width: 1.5),
                          ),
                          filled: true,
                          fillColor: MitraColors.bgCard,
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && i < 5) {
                            _otpFocuses[i + 1].requestFocus();
                          }
                          if (val.isEmpty && i > 0) {
                            _otpFocuses[i - 1].requestFocus();
                          }
                        },
                      ),
                    ),
                  )),
        ),
        const SizedBox(height: MitraSpacing.lg),

        _GradientButton(
            label: 'Verify & Login →', loading: _loading, onTap: _verifyOTP),
        const SizedBox(height: MitraSpacing.sm),

        Center(
          child: _resendTimer > 0
              ? Text('Resend in ${_resendTimer}s',
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 12,
                      color: MitraColors.textMuted))
              : TextButton(
                  onPressed: () {
                    setState(() {
                      _step = _LoginStep.phone;
                      for (final c in _otpCtrls) {
                        c.clear();
                      }
                    });
                  },
                  child: const Text('← Change Number / Resend OTP',
                      style: TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 13,
                          color: MitraColors.sky)),
                ),
        ),
      ];
}

// ── Internal gradient button ───────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final Color? color; // ✨ Restored parameter

  const _GradientButton({
    required this.label,
    required this.loading,
    required this.onTap,
    this.color, // ✨ Restored parameter
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            // ✨ If a theme color is provided, use it. Otherwise, use the Saffron gradient.
            color: color,
            gradient: color == null
                ? const LinearGradient(colors: MitraColors.gradientSaffron)
                : null,
            borderRadius: BorderRadius.circular(MitraRadius.pill),
          ),
          alignment: Alignment.center,
          child: loading
              ? const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2)
              : Text(label,
                  style: const TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white)),
        ),
      );
}
