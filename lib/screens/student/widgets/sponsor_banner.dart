import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../../services/api_service.dart';
import '../../../stores/auth_store.dart';

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
    final ads = await ref.read(sponsorAdsProvider.future);
    if (ads.isEmpty || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _SponsorInterstitial(ad: ads.first),
    );
  } catch (_) {/* fail silent */}
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
  const _SponsorInterstitial({required this.ad});

  @override
  State<_SponsorInterstitial> createState() => _SponsorInterstitialState();
}

class _SponsorInterstitialState extends State<_SponsorInterstitial> {
  static const _closeAfter = 10; // seconds until the X appears
  int _secondsLeft = _closeAfter;
  Timer? _timer;
  VideoPlayerController? _video;

  String get _mediaUrl => (widget.ad['media_url'] ??
          widget.ad['video_url'] ??
          widget.ad['image_url'] ??
          widget.ad['banner_url'] ??
          widget.ad['image'] ??
          '')
      .toString();

  String get _title =>
      (widget.ad['title'] ?? widget.ad['name'] ?? 'Sponsored').toString();

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

    // Prepare video if the creative is a video.
    final url = _mediaUrl;
    if (url.isNotEmpty && _looksLikeVideo(url)) {
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
      AdsAPI.impression({'ad_id': id}).catchError((_) => throw Exception());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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

              // "Sponsored" tag, top-left.
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
                  child: const Text('Sponsored',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ),
              ),

              // Timed close control, top-right.
              Positioned(
                top: 10,
                right: 10,
                child: _canClose
                    ? GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: _chip(const Icon(Icons.close,
                            color: Colors.white, size: 22)),
                      )
                    : _chip(Text('$_secondsLeft',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15))),
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
