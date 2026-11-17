// ═══════════════════════════════════════════════════════════════════════════
// Hero card album. One shield card per lesson that has a textbook page to
// scan; scanning the page unlocks it. Stars show how far the lesson went:
// ★ watched · ★★ quiz tried · ★★★ quiz mastered.
// Follows the active app theme; card faces use the subject hero's colours.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../providers/tr_ext.dart';
import '../screens/student/learn_screen.dart';
import '../stores/module_progress_store.dart';
import '../theme/theme_provider.dart';
import '../widgets/mitra_scaffold.dart';
import 'chiku.dart';
import 'fun_cards.dart';
import 'hero_catalog.dart';
import 'hero_svg.dart';

class AlbumCard {
  final String id, title, subject;
  final bool unlocked, isNew;
  final int stars; // 0..3
  final int? day; // yyyymmdd unlocked
  const AlbumCard(this.id, this.title, this.subject, this.unlocked, this.isNew, this.stars, this.day);
}

/// Every scannable lesson as a card, unlocked ones first.
final albumCardsProvider = Provider<List<AlbumCard>>((ref) {
  ref.watch(moduleProgressTickProvider);
  final catalog = ref.watch(arCatalogProvider).valueOrNull;
  if (catalog == null) return const [];
  final store = ref.watch(cardStoreProvider);
  final progress = ref.watch(moduleProgressStoreProvider);
  final unlocked = store.unlocked, seen = store.seen;
  final out = <AlbumCard>[];
  for (final e in catalog.bySubject.entries) {
    for (final l in e.value.where((l) => !l.locked)) {
      final scannable = (catalog.mindById[l.id] ?? '').isNotEmpty ||
          (catalog.targetImageById[l.id] ?? '').isNotEmpty;
      if (!scannable) continue;
      final qids = catalog.quizIdsByArId[l.id] ?? const <String>[];
      final best = qids.isEmpty ? 0 : qids.map(progress.bestPct).reduce(math.max);
      final stars = qids.any(progress.isMastered)
          ? 3
          : best > 0
              ? 2
              : progress.arWatched(l.id)
                  ? 1
                  : 0;
      final has = unlocked.containsKey(l.id);
      out.add(AlbumCard(l.id, l.title, e.key, has, has && !seen.contains(l.id), stars, unlocked[l.id]));
    }
  }
  out.sort((a, b) => (b.unlocked ? 1 : 0) - (a.unlocked ? 1 : 0));
  return out;
});

class CardAlbumScreen extends ConsumerStatefulWidget {
  const CardAlbumScreen({super.key});

  @override
  ConsumerState<CardAlbumScreen> createState() => _CardAlbumScreenState();
}

class _CardAlbumScreenState extends ConsumerState<CardAlbumScreen> {
  late final CardStore _store;

  @override
  void initState() {
    super.initState();
    _store = CardStore(ref.read(sharedPreferencesProvider));
  }

  @override
  void dispose() {
    // Leaving the album clears the NEW badges (Hero HQ refreshes on return).
    _store.markAllSeen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final cards = ref.watch(albumCardsProvider);
    final got = cards.where((c) => c.unlocked).length;
    return MitraScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: tp), onPressed: () => context.pop()),
        title: Text(context.trp(ref, 'fun_album_title', 'Hero cards · {got} of {all}', {'got': '$got', 'all': '${cards.length}'}),
            style: TextStyle(fontFamily: 'Baloo2', fontWeight: FontWeight.w800, color: tp)),
      ),
      body: Stack(children: [
        cards.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                      context.tr(ref, 'fun_album_empty', 'Cards appear here for lessons that have a textbook page to scan.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Mukta', color: ts)),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 96, 14, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.7,
                ),
                itemCount: cards.length,
                itemBuilder: (ctx, i) => HeroCardTile(card: cards[i], onTap: () => _open(cards[i])),
              ),
        const Positioned(top: 4, right: 10, child: ChikuCorner(size: 84)),
      ]),
    );
  }

  void _open(AlbumCard c) {
    if (!c.unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(ref, 'fun_card_locked_hint',
              "Scan this lesson's textbook page to unlock the card."))));
      return;
    }
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _CardZoom(card: c),
    );
  }
}

/// Shield-shaped card.
class HeroCardTile extends ConsumerWidget {
  final AlbumCard card;
  final VoidCallback? onTap;
  final double scale;
  const HeroCardTile({super.key, required this.card, this.onTap, this.scale = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = heroForSubject(card.subject);
    final hl = Theme.of(context).colorScheme.primary;
    final ts = ThemeHelper.ctxTextSecondary(context);
    final face = card.unlocked
        ? Container(
            decoration: BoxDecoration(
              color: hero.main,
              border: Border.all(color: hero.accent, width: 3 * scale),
            ),
            padding: EdgeInsets.fromLTRB(6 * scale, 10 * scale, 6 * scale, 14 * scale),
            child: Column(children: [
              SvgPicture.string(heroEmblemSvg(hero), width: 40 * scale, height: 40 * scale),
              SizedBox(height: 4 * scale),
              Expanded(
                child: Center(
                  child: Text(card.title,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5 * scale,
                          height: 1.1,
                          color: Colors.white)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    3,
                    (i) => Icon(i < card.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 14 * scale, color: const Color(0xFFFDE68A))),
              ),
            ]),
          )
        : Container(
            decoration: BoxDecoration(
              color: ThemeHelper.ctxGlassFill(context),
              border: Border.all(color: ThemeHelper.ctxGlassBorder(context), width: 2),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, color: ts, size: 26 * scale),
              const SizedBox(height: 4),
              Text(card.subject,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontFamily: 'Mukta', fontSize: 11 * scale, color: ts)),
            ]),
          );
    return Semantics(
      button: onTap != null,
      label: card.unlocked ? '${card.title}, ${card.stars} stars' : '${card.subject}, locked',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: ClipPath(clipper: _ShieldClipper(), child: face)),
          if (card.isNew)
            Positioned(
              top: -4,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: hl, borderRadius: BorderRadius.circular(8)),
                child: Text(context.tr(ref, 'fun_new', 'NEW'),
                    style: const TextStyle(fontFamily: 'SpaceMono', fontWeight: FontWeight.w700, fontSize: 10, color: Colors.black)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * .5, 0)
    ..lineTo(s.width, s.height * .1)
    ..lineTo(s.width * .96, s.height * .64)
    ..quadraticBezierTo(s.width * .85, s.height * .88, s.width * .5, s.height)
    ..quadraticBezierTo(s.width * .15, s.height * .88, s.width * .04, s.height * .64)
    ..lineTo(0, s.height * .1)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Tapped card: flips in, big, with its details.
class _CardZoom extends ConsumerStatefulWidget {
  final AlbumCard card;
  const _CardZoom({required this.card});

  @override
  ConsumerState<_CardZoom> createState() => _CardZoomState();
}

class _CardZoomState extends ConsumerState<_CardZoom> with SingleTickerProviderStateMixin {
  late final AnimationController _flip =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final d = c.day;
    final date = d == null ? '' : '${d % 100}/${(d ~/ 100) % 100}/${d ~/ 10000}';
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _flip,
          builder: (_, child) {
            final t = Curves.easeOutBack.transform(_flip.value);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY((1 - t) * math.pi),
              child: child,
            );
          },
          child: SizedBox(width: 210, height: 300, child: HeroCardTile(card: c, scale: 2)),
        ),
        const SizedBox(height: 14),
        Text(c.subject,
            style: const TextStyle(fontFamily: 'Mukta', fontSize: 14, color: Colors.white70)),
        if (date.isNotEmpty)
          Text(context.trp(ref, 'fun_card_unlocked_on', 'Unlocked on {date}', {'date': date}),
              style: const TextStyle(fontFamily: 'Mukta', fontSize: 13, color: Colors.white60)),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr(ref, 'fun_close', 'Close'),
              style: const TextStyle(fontFamily: 'Mukta', fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ]),
    );
  }
}
