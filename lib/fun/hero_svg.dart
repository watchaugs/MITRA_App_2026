// ═══════════════════════════════════════════════════════════════════════════
// Draws a MITRA hero as SVG strings (rendered by flutter_svg), split into
// layers so hero_view.dart can animate them separately:
//   aura  — spinning power ring (Gyani level only)
//   back  — the girl hero's long hair (behind the cape)
//   cape  — flutters
//   body  — everything else
//   eyes  — blink
// All layers share one 240 × 320 canvas, so they stack exactly.
//
// Costume level (0..4) adds pieces as the subject's XP grows:
//   0 (20%) hero T-shirt + emblem patch · 1 (40%) mask + full suit
//   2 (60%) cape + power belt · 3 (80%) gloves, boots, shoulder guards
//   4 (100%) gold armour trim, headpiece, power aura
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import 'hero_catalog.dart';

class HeroLayers {
  final String aura, back, cape, body, eyes;
  const HeroLayers(this.aura, this.back, this.cape, this.body, this.eyes);
}

const double kHeroW = 240, kHeroH = 320;
const String _ol = '#1A1033'; // outline ink

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

/// Lighter (a > 0) or darker (a < 0) shade, like the dashboard preview.
String _shade(Color c, double a) {
  final v = c.toARGB32();
  int r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
  final t = a < 0 ? 0 : 255;
  final p = a.abs();
  r = ((t - r) * p + r).round();
  g = ((t - g) * p + g).round();
  b = ((t - b) * p + b).round();
  return '#${((r << 16) | (g << 8) | b).toRadixString(16).padLeft(6, '0')}';
}

String _svg(String inner) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">$inner</svg>';

String _emblem(String k, String c, String bg) {
  switch (k) {
    case 'atom':
      return '<ellipse rx="9" ry="3.4" fill="none" stroke="$c" stroke-width="1.6"/>'
          '<ellipse rx="9" ry="3.4" fill="none" stroke="$c" stroke-width="1.6" transform="rotate(60)"/>'
          '<ellipse rx="9" ry="3.4" fill="none" stroke="$c" stroke-width="1.6" transform="rotate(-60)"/>'
          '<circle r="2" fill="$c"/>';
    case 'bolt':
      return '<path d="M2 -10 L-6 2 L-1 2 L-3 10 L6 -3 L1 -3Z" fill="$c"/>';
    case 'flask':
      return '<path d="M-3 -9 L3 -9 M-2 -9 L-2 -2 L-8 7 C-9 9 -8 10 -6 10 L6 10 C8 10 9 9 8 7 L2 -2 L2 -9" fill="none" stroke="$c" stroke-width="1.6" stroke-linejoin="round"/>'
          '<path d="M-6 6 L6 6 L7.4 8.5 L-7.4 8.5Z" fill="$c"/>';
    case 'dna':
      return '<path d="M-5 -10 C5 -5 5 5 -5 10 M5 -10 C-5 -5 -5 5 5 10" fill="none" stroke="$c" stroke-width="1.7"/>'
          '<path d="M-3 -6 L3 -6 M-4 0 L4 0 M-3 6 L3 6" stroke="$c" stroke-width="1.3"/>';
    case 'pi': // drawn, so no font is needed
      return '<path d="M-8 -6 L8 -6 M-4 -6 C-4 0 -5 6 -7 9 M4 -6 L4 7 C4 9 6 9 8 8" fill="none" stroke="$c" stroke-width="2.2" stroke-linecap="round"/>';
    case 'tree':
      return '<circle cy="-3" r="7" fill="$c"/><rect x="-1.6" y="2" width="3.2" height="8" fill="$c"/>';
    case 'hour':
      return '<path d="M-6 -9 L6 -9 L0 0 L6 9 L-6 9 L0 0Z" fill="none" stroke="$c" stroke-width="1.7" stroke-linejoin="round"/>'
          '<path d="M-3 6 L3 6 L0 2Z" fill="$c"/>';
    case 'compass':
      return '<circle r="9" fill="none" stroke="$c" stroke-width="1.5"/>'
          '<path d="M0 -8 L3 0 L0 8 L-3 0Z" fill="$c"/><circle r="1.6" fill="$bg"/>';
    case 'scale':
      return '<path d="M0 -9 L0 8 M-7 -5 L7 -5 M-6 8 L6 8" stroke="$c" stroke-width="1.6"/>'
          '<path d="M-7 -5 L-10 2 L-4 2Z M7 -5 L4 2 L10 2Z" fill="$c"/>';
    case 'people':
      return '<circle cx="-5" cy="-3" r="3" fill="$c"/><circle cx="5" cy="-3" r="3" fill="$c"/>'
          '<circle cy="-5" r="3.4" fill="$c"/><path d="M-10 8 C-9 1 9 1 10 8Z" fill="$c"/>';
    case 'coin': // rupee sign drawn as lines
      return '<circle r="9" fill="none" stroke="$c" stroke-width="1.6"/>'
          '<path d="M-4 -5 L4 -5 M-4 -2 L4 -2 M-3 -5 C3 -5 3 1 -3 1 L3 6" fill="none" stroke="$c" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>';
    case 'quill':
      return '<path d="M7 -10 C-4 -6 -6 4 -7 10 C-2 4 4 0 7 -10Z" fill="$c"/>'
          '<path d="M-7 10 L-2 3" stroke="$bg" stroke-width="1"/>';
    case 'a': // Devanagari "अ" (Mukta is bundled and covers Devanagari)
      return '<text y="6" text-anchor="middle" font-family="Mukta" font-size="16" font-weight="700" fill="$c">अ</text>';
    case 'bubble':
      return '<path d="M-9 -7 L9 -7 L9 4 L-1 4 L-5 9 L-5 4 L-9 4Z" fill="$c"/>'
          '<circle cx="-4" cy="-1.5" r="1.4" fill="$bg"/><circle cy="-1.5" r="1.4" fill="$bg"/><circle cx="4" cy="-1.5" r="1.4" fill="$bg"/>';
    case 'scroll':
      return '<rect x="-8" y="-7" width="16" height="14" rx="2" fill="none" stroke="$c" stroke-width="1.6"/>'
          '<path d="M-5 -3 L5 -3 M-5 1 L5 1 M-5 4 L2 4" stroke="$c" stroke-width="1.2"/>';
    case 'code':
      return '<path d="M-4 -6 L-10 0 L-4 6 M4 -6 L10 0 L4 6 M2 -8 L-2 8" fill="none" stroke="$c" stroke-width="1.8" stroke-linecap="round"/>';
    default: // book
      return '<path d="M0 -6 C-4 -9 -9 -8 -10 -7 L-10 8 C-8 6 -4 6 0 9 C4 6 8 6 10 8 L10 -7 C9 -8 4 -9 0 -6Z M0 -6 L0 9" fill="none" stroke="$c" stroke-width="1.5"/>';
  }
}

String _mask(String k, String c) {
  switch (k) {
    case 'visor':
      return '<path d="M90 62 C100 56 140 56 150 62 L148 78 C138 82 102 82 92 78Z" fill="$c" stroke="$_ol" stroke-width="1.4"/>';
    case 'goggle':
      return '<rect x="86" y="62" width="68" height="18" rx="9" fill="$c" stroke="$_ol" stroke-width="1.4"/>';
    case 'leaf':
      return '<path d="M84 66 C96 54 112 58 120 66 C128 58 144 54 156 66 C148 82 130 84 120 76 C110 84 92 82 84 66Z" fill="$c" stroke="$_ol" stroke-width="1.4"/>';
    case 'star':
      return '<path d="M86 64 L98 60 L108 64 L120 60 L132 64 L142 60 L154 64 L150 80 L130 80 L120 74 L110 80 L90 80Z" fill="$c" stroke="$_ol" stroke-width="1.4"/>';
    case 'wing':
      return '<path d="M78 58 C90 62 100 60 120 66 C140 60 150 62 162 58 C156 74 142 84 120 76 C98 84 84 74 78 58Z" fill="$c" stroke="$_ol" stroke-width="1.4"/>';
    default: // domino
      return '<path d="M90 70 C94 58 112 58 120 66 C128 58 146 58 150 70 C148 82 130 84 120 76 C110 84 92 82 90 70Z" fill="$c" stroke="$_ol" stroke-width="1.4"/>';
  }
}

/// [girl]: girl version; [level]: costume level 0..4.
HeroLayers buildHeroLayers(HeroDef h,
    {required bool girl, required int level}) {
  final t = level.clamp(0, 4);
  final m = _hex(h.main),
      ac = _hex(h.accent),
      sk = _hex(h.skin),
      hr = _hex(h.hair);
  final dk = _shade(h.main, -.35),
      skd = _shade(h.skin, -.18),
      lin = _shade(h.accent, -.15);
  final acDk = _shade(h.accent, -.25), acDk3 = _shade(h.accent, -.3);
  final gold = t >= 4;

  // ── aura (Gyani) ──
  final aura = t >= 4
      ? _svg('<circle cx="120" cy="170" r="98" fill="$ac" opacity="0.08"/>'
          '<circle cx="120" cy="170" r="112" fill="none" stroke="$ac" stroke-width="2" stroke-dasharray="6 14" opacity="0.7"/>')
      : '';

  // ── girl's long hair behind the cape ──
  final back = girl
      ? _svg(
          '<path d="M84 64 C80 100 86 128 96 138 L144 138 C154 128 160 100 156 64Z" fill="$hr" stroke="$_ol" stroke-width="1.4"/>')
      : '';

  // ── cape (Vidwan and up) ──
  final cape = t >= 2
      ? _svg(
          '<path d="M88 112 C66 152 58 232 64 296 L176 296 C182 232 174 152 152 112Z" fill="$ac" stroke="$_ol" stroke-width="1.6"/>'
          '<path d="M96 122 C80 160 74 230 78 288 L162 288 C166 230 160 160 144 122Z" fill="$lin"/>'
          '<path d="M104 140 C98 190 96 240 98 288 M136 140 C142 190 144 240 142 288 M120 130 L120 288" stroke="$acDk3" stroke-width="1.4" fill="none" opacity="0.6"/>')
      : '';

  // ── body ──
  final o = StringBuffer();
  final legC = t >= 1 ? dk : '#334E7A'; // jeans at level 0
  o.write(
      '<rect x="98" y="198" width="20" height="84" rx="9" fill="$legC" stroke="$_ol" stroke-width="1.4"/>'
      '<rect x="122" y="198" width="20" height="84" rx="9" fill="$legC" stroke="$_ol" stroke-width="1.4"/>'
      '<rect x="103" y="204" width="5" height="70" rx="2.5" fill="#FFFFFF" opacity="0.12"/>');
  if (girl && t == 0) {
    o.write(
        '<path d="M92 192 L148 192 L156 236 L84 236Z" fill="$ac" stroke="$_ol" stroke-width="1.4"/>');
  }
  if (girl && t >= 1) {
    o.write(
        '<path d="M92 190 L148 190 L156 226 C140 232 100 232 84 226Z" fill="$m" stroke="$_ol" stroke-width="1.4"/>'
        '<path d="M100 196 L96 226 M120 196 L120 230 M140 196 L144 226" stroke="$dk" stroke-width="1.2" opacity="0.6"/>');
  }
  if (t >= 3) {
    o.write(
        '<path d="M95 244 L121 244 L121 286 C121 292 92 292 92 286Z" fill="$ac" stroke="$_ol" stroke-width="1.4"/>'
        '<path d="M119 244 L145 244 L148 286 C148 292 119 292 119 286Z" fill="$ac" stroke="$_ol" stroke-width="1.4"/>'
        '<rect x="94" y="240" width="28" height="8" rx="3" fill="$acDk" stroke="$_ol" stroke-width="1.2"/>'
        '<rect x="118" y="240" width="28" height="8" rx="3" fill="$acDk" stroke="$_ol" stroke-width="1.2"/>');
  } else {
    o.write(
        '<path d="M92 276 L120 276 L120 290 L88 290 C86 284 88 278 92 276Z" fill="#F8FAFC" stroke="$_ol" stroke-width="1.4"/>'
        '<path d="M120 276 L148 276 C152 278 154 284 152 290 L120 290Z" fill="#F8FAFC" stroke="$_ol" stroke-width="1.4"/>'
        '<path d="M90 286 L120 286 M120 286 L152 286" stroke="$ac" stroke-width="2"/>');
  }
  final torso = t == 0 ? ac : m;
  o.write(
      '<path d="M92 122 C92 112 100 106 110 106 L130 106 C140 106 148 112 148 122 L146 200 L94 200Z" fill="$torso" stroke="$_ol" stroke-width="1.6"/>'
      '<path d="M136 110 C144 116 146 130 145 200 L134 200 C138 160 138 128 136 110Z" fill="#000000" opacity="0.18"/>'
      '<path d="M100 114 C97 130 97 160 99 196" stroke="#FFFFFF" stroke-width="3" opacity="0.18" fill="none" stroke-linecap="round"/>');
  if (t == 0) {
    o.write(
        '<path d="M92 122 C86 126 82 134 80 142 L92 146Z M148 122 C154 126 158 134 160 142 L148 146Z" fill="$ac" stroke="$_ol" stroke-width="1.4"/>'
        '<circle cx="120" cy="146" r="11" fill="$m"/>'
        '<g transform="translate(120 146) scale(0.8)">${_emblem(h.emblem, ac, m)}</g>');
  } else {
    final ec = gold ? '#FDE68A' : ac;
    o.write(
        '<path d="M104 108 L120 132 L136 108" fill="none" stroke="$ac" stroke-width="3"/>'
        '<circle cx="120" cy="150" r="17" fill="$ec" stroke="$_ol" stroke-width="1.4"/>'
        '<circle cx="120" cy="150" r="13.5" fill="$dk"/>'
        '<g transform="translate(120 150) scale(1.05)">${_emblem(h.emblem, ec, dk)}</g>');
    if (gold) {
      o.write(
          '<circle cx="120" cy="150" r="19" fill="none" stroke="#FDE68A" stroke-width="2"/>');
    }
  }
  if (gold) {
    o.write(
        '<path d="M96 118 C104 126 136 126 144 118 M98 188 L142 188" stroke="#FBBF24" stroke-width="2.4" fill="none"/>'
        '<path d="M110 106 L120 116 L130 106" stroke="#FBBF24" stroke-width="2.4" fill="none"/>');
  }
  if (t >= 2) {
    o.write(
        '<rect x="93" y="190" width="54" height="11" rx="4" fill="#FBBF24" stroke="$_ol" stroke-width="1.4"/>'
        '<circle cx="120" cy="195.5" r="7" fill="$dk" stroke="#FBBF24" stroke-width="2"/>'
        '<g transform="translate(120 195.5) scale(0.45)">${_emblem(h.emblem, '#FDE68A', dk)}</g>');
  }
  final armC = t >= 1 ? m : sk, glv = t >= 3 ? ac : sk;
  // left arm (down)
  o.write(
      '<path d="M96 122 C84 136 78 160 76 186" stroke="$_ol" stroke-width="17" fill="none" stroke-linecap="round"/>'
      '<path d="M96 122 C84 136 78 160 76 186" stroke="$armC" stroke-width="14" fill="none" stroke-linecap="round"/>');
  if (t == 0) {
    o.write(
        '<path d="M86 160 C82 170 78 178 76 186" stroke="$sk" stroke-width="13" fill="none" stroke-linecap="round"/>');
  }
  o.write(
      '<circle cx="76" cy="192" r="9" fill="$glv" stroke="$_ol" stroke-width="1.4"/>');
  if (t >= 3) {
    o.write(
        '<rect x="66" y="176" width="20" height="8" rx="3" fill="$acDk" stroke="$_ol" stroke-width="1.2"/>');
  }
  // right arm (raised fist)
  o.write(
      '<path d="M144 122 C158 112 168 96 174 70" stroke="$_ol" stroke-width="17" fill="none" stroke-linecap="round"/>'
      '<path d="M144 122 C158 112 168 96 174 70" stroke="$armC" stroke-width="14" fill="none" stroke-linecap="round"/>');
  if (t == 0) {
    o.write(
        '<path d="M162 102 C167 92 171 82 174 70" stroke="$sk" stroke-width="13" fill="none" stroke-linecap="round"/>');
  }
  o.write(
      '<circle cx="175" cy="62" r="10" fill="$glv" stroke="$_ol" stroke-width="1.4"/>'
      '<path d="M169 58 L181 58 M169 62 L181 62" stroke="$_ol" stroke-width="1" opacity="0.5"/>');
  if (t >= 3) {
    o.write(
        '<rect x="164" y="72" width="22" height="8" rx="3" fill="$acDk" stroke="$_ol" stroke-width="1.2" transform="rotate(-14 175 76)"/>'
        '<ellipse cx="94" cy="118" rx="13" ry="9" fill="$ac" stroke="$_ol" stroke-width="1.4"/>'
        '<ellipse cx="146" cy="118" rx="13" ry="9" fill="$ac" stroke="$_ol" stroke-width="1.4"/>');
  }
  // neck, ears, head
  o.write('<rect x="112" y="96" width="16" height="14" fill="$skd"/>'
      '<circle cx="86" cy="72" r="6" fill="$sk" stroke="$_ol" stroke-width="1.2"/>'
      '<circle cx="154" cy="72" r="6" fill="$sk" stroke="$_ol" stroke-width="1.2"/>'
      '<circle cx="120" cy="68" r="34" fill="$sk" stroke="$_ol" stroke-width="1.6"/>'
      '<path d="M98 92 C110 102 130 102 142 92" stroke="$skd" stroke-width="3" fill="none" opacity="0.5"/>');
  if (girl) {
    o.write(
        '<path d="M86 64 C84 38 104 28 120 30 C140 30 158 42 154 66 C146 50 132 44 120 46 C106 44 92 52 86 64Z" fill="$hr" stroke="$_ol" stroke-width="1.4"/>'
        '<path d="M118 32 C114 40 108 46 98 50" stroke="${_shade(h.hair, .25)}" stroke-width="2" fill="none"/>'
        '<path d="M152 46 C170 40 176 58 168 76 C164 64 160 58 154 56Z" fill="$hr" stroke="$_ol" stroke-width="1.4"/>'
        '<rect x="150" y="44" width="9" height="9" rx="3" fill="$ac" stroke="$_ol" stroke-width="1"/>');
  } else {
    o.write(
        '<path d="M86 64 C82 42 96 26 112 26 L116 18 L122 26 L130 20 L132 28 C148 30 158 44 154 64 C148 52 140 48 132 48 L128 40 L122 48 L114 42 L110 50 C100 50 92 56 86 64Z" fill="$hr" stroke="$_ol" stroke-width="1.4"/>'
        '<path d="M112 30 L116 22 M128 32 L130 24" stroke="${_shade(h.hair, .3)}" stroke-width="1.6"/>');
  }
  if (t >= 1) o.write(_mask(h.mask, dk));
  if (t == 0) {
    o.write(
        '<path d="M99 58 Q106 54 113 58 M127 58 Q134 54 141 58" stroke="$hr" stroke-width="2.4" fill="none" stroke-linecap="round"/>');
  }
  // nose, smile, cheeks
  o.write(
      '<path d="M118 80 Q120 83 122 80" stroke="$skd" stroke-width="1.6" fill="none"/>'
      '<path d="M110 88 Q120 96 130 88" stroke="#7C2D12" stroke-width="2.2" fill="none" stroke-linecap="round"/>'
      '<path d="M114 90 Q120 94 126 90" fill="#FFFFFF" opacity="0.8"/>'
      '<circle cx="98" cy="84" r="4" fill="#F472B6" opacity="0.35"/>'
      '<circle cx="142" cy="84" r="4" fill="#F472B6" opacity="0.35"/>');
  if (gold) {
    o.write(
        '<path d="M92 46 C104 38 136 38 148 46" stroke="#FBBF24" stroke-width="4" fill="none" stroke-linecap="round"/>'
        '<path d="M120 34 L126 42 L120 50 L114 42Z" fill="$ac" stroke="#FBBF24" stroke-width="2"/>');
  }
  final body = _svg(o.toString());

  // ── eyes (blink layer) ──
  final goggle = t >= 1 && h.mask == 'goggle';
  final ew = goggle ? '#E0F2FE' : '#FFFFFF';
  final e = StringBuffer()
    ..write(
        '<ellipse cx="106" cy="70" rx="7.5" ry="8.5" fill="$ew" stroke="$_ol" stroke-width="1"/>'
        '<ellipse cx="134" cy="70" rx="7.5" ry="8.5" fill="$ew" stroke="$_ol" stroke-width="1"/>'
        '<circle cx="107" cy="71" r="4.6" fill="#3B2410"/><circle cx="135" cy="71" r="4.6" fill="#3B2410"/>'
        '<circle cx="107" cy="71" r="2.2" fill="#0B0B0B"/><circle cx="135" cy="71" r="2.2" fill="#0B0B0B"/>'
        '<circle cx="108.6" cy="69" r="1.5" fill="#FFFFFF"/><circle cx="136.6" cy="69" r="1.5" fill="#FFFFFF"/>');
  if (girl) {
    e.write(
        '<path d="M99 63 L97 60 M103 61.5 L102 58.5 M141 63 L143 60 M137 61.5 L138 58.5" stroke="$_ol" stroke-width="1.3" stroke-linecap="round"/>');
  }
  final eyes = _svg(e.toString());

  return HeroLayers(aura, back, cape, body, eyes);
}

/// The hero's emblem as a round badge (40 × 40), for hero cards and medals.
String heroEmblemSvg(HeroDef h) {
  final ac = _hex(h.accent), dk = _shade(h.main, -.35);
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">'
      '<circle cx="20" cy="20" r="19" fill="$ac" stroke="$_ol" stroke-width="1.4"/>'
      '<circle cx="20" cy="20" r="15" fill="$dk"/>'
      '<g transform="translate(20 20) scale(1.15)">${_emblem(h.emblem, ac, dk)}</g>'
      '</svg>';
}
