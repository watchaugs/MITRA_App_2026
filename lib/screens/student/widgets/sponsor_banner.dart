import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api_service.dart';
import '../../../stores/auth_store.dart';
import '../../../providers/app_prefs.dart';

/// Geofenced sponsor ads from the dashboard, scoped to the student's state.
/// Empty on error or when there are none (interstitial then just won't show).
final sponsorAdsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  final state = user?.assignedState ?? '';
  try {
    final res = await AdsAPI.list({if (state.isNotEmpty) 'state': state});
    final raw = res.data is Map ? res.data['data'] : null;
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  } catch (_) {/* fail silent */}
  return const [];
});

// Only show the interstitial once per app launch.
bool _sponsorInterstitialShown = false;

/// Fetches the first geofenced ad and shows it as a full-screen overlay.
/// Safe to call from build via a post-frame callback — it self-guards.
Future<void> maybeShowSponsorInterstitial(
    BuildContext context, WidgetRef ref) async {
  if (_sponsorInterstitialShown) return;
  _sponsorInterstitialShown = true;
  try {
    // Respect the dashboard's frequency cap ({ cap, window_hours }): show at
    // most `cap` sponsor screens per rolling `window_hours`. Counted on-device
    // with SharedPreferences so no server round-trip is needed to decide.
    if (!await _sponsorCapAllows()) return;
    final ads = await ref.read(sponsorAdsProvider.future);
    if (ads.isEmpty || !context.mounted) return;
    final dataSaver = ref.read(appPrefsProvider).dataSaver;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _SponsorInterstitial(ad: ads.first, dataSaver: dataSaver),
    );
  } catch (_) {/* fail silent */}
}

/// Returns true if another sponsor screen is allowed right now, per the
/// dashboard's { cap, window_hours } setting. Records this show when allowed.
Future<bool> _sponsorCapAllows() async {
  try {
    int cap = 3;
    int windowHours = 24;
    try {
      final res = await AdsAPI.frequency();
      final d = res.data;
      if (d is Map) {
        cap = (d['cap'] ?? d['daily_push'] ?? 3) is int
            ? (d['cap'] ?? d['daily_push'] ?? 3) as int
            : int.tryParse('${d['cap'] ?? d['daily_push'] ?? 3}') ?? 3;
        windowHours = (d['window_hours'] ?? 24) is int
            ? (d['window_hours'] ?? 24) as int
            : int.tryParse('${d['window_hours'] ?? 24}') ?? 24;
      }
    } catch (_) {/* fall back to 3 / 24h */}

    if (cap <= 0) return false; // 0 = ads effectively off

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = windowHours * 3600 * 1000;
    // Stored as a list of show-timestamps (ms); keep only those in-window.
    final raw = prefs.getStringList('sponsor_show_ts') ?? const [];
    final kept = raw
        .map((s) => int.tryParse(s) ?? 0)
        .where((t) => t > 0 && (now - t) < windowMs)
        .toList();
    if (kept.length >= cap) return false;
    kept.add(now);
    await prefs.setStringList(
        'sponsor_show_ts', kept.map((t) => '$t').toList());
    return true;
  } catch (_) {
    return true; // never block the app over a prefs error
  }
}

bool _looksLikeVideo(String url) {
  final u = url.toLowerCase();
  return u.endsWith('.mp4') ||
      u.endsWith('.mov') ||
      u.endsWith('.webm') ||
      u.endsWith('.m4v');
}

class _SponsorInterstitial extends StatefulWidget {
  final Map<String, dynamic> ad;
  final bool dataSaver;
  const _SponsorInterstitial({required this.ad, this.dataSaver = false});

  @override
  State<_SponsorInterstitial> createState() => _SponsorInterstitialState();
}

class _SponsorInterstitialState extends State<_SponsorInterstitial> {
  // Dashboard-controlled popup behaviour (per campaign), with safe defaults.
  late final int _closeAfter = _intFrom(widget.ad['close_after_seconds'], 10);
  late final int _autoDismiss = _intFrom(widget.ad['auto_dismiss_seconds'], 0);
  late final bool _skippable = widget.ad['skippable'] != false;
  late int _secondsLeft = _closeAfter;
  Timer? _timer;
  Timer? _autoDismissTimer;

  static int _intFrom(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  VideoPlayerController? _video;
  final DateTime _shownAt = DateTime.now();
  bool _engagementSent = false;

  String get _mediaUrl => (widget.ad['media_url'] ??
          widget.ad['video_url'] ??
          widget.ad['image_url'] ??
          widget.ad['banner_url'] ??
          widget.ad['image'] ??
          '')
      .toString();

  String get _title =>
      (widget.ad['title'] ?? widget.ad['name'] ?? 'Announcement').toString();

  bool get _canClose => _secondsLeft <= 0;

  @override
  void initState() {
    super.initState();

    // Count down to the close button.
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, _closeAfter));
      if (_secondsLeft == 0) t.cancel();
    });

    // Auto-dismiss: close the popup on its own after N seconds (0 = never).
    if (_autoDismiss > 0) {
      _autoDismissTimer = Timer(Duration(seconds: _autoDismiss), () {
        if (mounted) _close();
      });
    }

    // Prepare video if the creative is a video — unless Data saver is on,
    // in which case we never download video (shows the title card instead).
    final url = _mediaUrl;
    if (!widget.dataSaver && url.isNotEmpty && _looksLikeVideo(url)) {
      _video = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setLooping(true)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _video?.play();
        }).catchError((_) {/* fall back to blank */});
    }

    // Fire-and-forget impression telemetry.
    final id = (widget.ad['id'] ?? widget.ad['ad_id'] ?? '').toString();
    if (id.isNotEmpty) {
      unawaited(AdsAPI.impression({'ad_id': id}).then((_) {}, onError: (_) {}));
    }
  }

  /// Ad engagement depth (Table A): how long the overlay was shown, whether
  /// the countdown completed, and video completion %. Sent once, on close.
  void _reportEngagement() {
    if (_engagementSent) return;
    _engagementSent = true;
    final id = (widget.ad['id'] ?? widget.ad['ad_id'] ?? '').toString();
    if (id.isEmpty) return;
    double? completionPct;
    final v = _video;
    if (v != null &&
        v.value.isInitialized &&
        v.value.duration.inMilliseconds > 0) {
      completionPct = (v.value.position.inMilliseconds /
              v.value.duration.inMilliseconds *
              100)
          .clamp(0, 100)
          .toDouble();
    }
    unawaited(AdsAPI.engagement({
      'campaign_id': id,
      'event_type': 'close',
      'view_time_ms': DateTime.now().difference(_shownAt).inMilliseconds,
      'completed': _secondsLeft <= 0,
      if (completionPct != null) 'completion_pct': completionPct,
      'media_type': _video != null ? 'video' : 'image',
    }).then((_) {}, onError: (_) {}));
  }

  // Single close path (used by the X and the auto-dismiss timer).
  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _reportEngagement();
    _timer?.cancel();
    _autoDismissTimer?.cancel();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero, // we add our own padding below
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        child: Padding(
          // Padding from all 4 screen edges.
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              // Media card fills the padded area.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: _buildMedia(),
                  ),
                ),
              ),

              // Departmental "Notice" tag, top-left (this is an official school/
              // department announcement, NOT a commercial ad).
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('📢 Notice',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ),
              ),

              // Timed close control, top-right: a progress ring fills over the
              // countdown, then becomes a tappable X. If the campaign is not
              // skippable, the X only appears once auto-dismiss is imminent
              // (i.e. the student can't close early — they watch it through).
              Positioned(
                top: 10,
                right: 10,
                child: (_canClose && _skippable)
                    ? GestureDetector(
                        onTap: _close,
                        child: _chip(const Icon(Icons.close,
                            color: Colors.white, size: 22)),
                      )
                    : _chip(
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _closeAfter == 0
                                    ? 1
                                    : (_closeAfter - _secondsLeft) /
                                        _closeAfter,
                                strokeWidth: 3,
                                backgroundColor: Colors.white24,
                                valueColor:
                                    const AlwaysStoppedAnimation(Colors.white),
                              ),
                              Text(
                                _secondsLeft > 0 ? '$_secondsLeft' : '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(Widget child) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: child,
      );

  Widget _buildMedia() {
    final url = _mediaUrl;
    if (url.isEmpty) {
      return Text(_title,
          style: const TextStyle(color: Colors.white, fontSize: 18));
    }

    // Video creative.
    if (_video != null) {
      if (_video!.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _video!.value.size.width,
            height: _video!.value.size.height,
            child: VideoPlayer(_video!),
          ),
        );
      }
      return const CircularProgressIndicator(color: Colors.white);
    }

    // Image creative.
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) =>
          const CircularProgressIndicator(color: Colors.white),
      errorWidget: (_, __, ___) => Text(_title,
          style: const TextStyle(color: Colors.white, fontSize: 18)),
    );
  }
}
