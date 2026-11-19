// ═══════════════════════════════════════════════════════════════════════════
// MITRA heroes — "Bio-tech armour" look. Every hero in hero_catalog.dart, boy
// and girl, drawn as SVG layers on one 400 × 600 canvas so hero_view.dart can
// animate them separately:
//   aura   — Gyani power rings (spins)        ground — shadow + floor ring
//   cape   — energy cape (sways)              back   — the girl's long hair
//   body   — everything else                  glow   — light lines (pulse)
//   eyes   — blink
//   flash, shock, shock2, sparks, vflare, impact — tap power-move effects
//
// Costume level (0..4) adds pieces as the subject's achievement grows:
//   0 (20%) bio-suit + emblem patch · 1 (40%) glowing visor + armour plates
//   2 (60%) energy cape + power belt · 3 (80%) gauntlets, armoured boots,
//   shoulder guards · 4 (100%) gold trim, crest, power aura.
//
// Colours come from the hero's main / accent / skin / hair. Glows are soft
// gradients and layered strokes (flutter_svg draws no blur filters).
// Generated from the design source; edit there and regenerate.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hero_catalog.dart';

const double kBioW = 400, kBioH = 600;

class BiotechLayers {
  final String aura, ground, back, cape, body, glow, eyes;
  final String flash, shock, shock2, sparks, vflare, impact;
  const BiotechLayers({
    required this.aura,
    required this.ground,
    required this.back,
    required this.cape,
    required this.body,
    required this.glow,
    required this.eyes,
    required this.flash,
    required this.shock,
    required this.shock2,
    required this.sparks,
    required this.vflare,
    required this.impact,
  });
}

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Toward white (w) or black (k) by [a].
Color _mix(Color c, bool white, double a) => Color.lerp(
    c, white ? const Color(0xFFFFFFFF) : const Color(0xFF000000), a)!;

/// Bright, saturated glow version of a colour.
Color _neon(Color c) {
  final h = HSLColor.fromColor(c);
  return HSLColor.fromAHSL(1, h.hue, math.min(1.0, h.saturation * 1.1 + .2),
          (h.lightness + .3).clamp(.62, .7).toDouble())
      .toColor();
}

Map<String, String> _tokens(HeroDef h) {
  final src = <String, Color>{
    'main': h.main,
    'accent': h.accent,
    'skin': h.skin,
    'hair': h.hair
  };
  final c = <String, Color>{};
  c['M'] = (c['main'] ?? src['main']!);
  c['GL'] = _neon((c['main'] ?? src['main']!));
  c['AN'] = _neon((c['accent'] ?? src['accent']!));
  c['UND'] = _mix((c['main'] ?? src['main']!), false, 0.72);
  c['TR'] = _mix((c['main'] ?? src['main']!), false, 0.8);
  c['BADGE'] = _mix((c['main'] ?? src['main']!), false, 0.82);
  c['MT0'] = _mix((c['main'] ?? src['main']!), true, 0.6);
  c['MT2'] = _mix((c['main'] ?? src['main']!), false, 0.35);
  c['MT3'] = _mix((c['GL'] ?? src['GL']!), false, 0.1);
  c['MT4'] = _mix((c['main'] ?? src['main']!), false, 0.5);
  c['MT5'] = _mix((c['main'] ?? src['main']!), false, 0.7);
  c['VS0'] = _mix((c['GL'] ?? src['GL']!), true, 0.7);
  c['VS2'] = _mix((c['main'] ?? src['main']!), false, 0.2);
  c['ACD'] = _mix((c['accent'] ?? src['accent']!), false, 0.3);
  c['ACL'] = _mix((c['accent'] ?? src['accent']!), true, 0.45);
  c['HXC'] = _mix((c['accent'] ?? src['accent']!), true, 0.5);
  c['SK'] = (c['skin'] ?? src['skin']!);
  c['SKL'] = _mix((c['skin'] ?? src['skin']!), true, 0.25);
  c['SKD'] = _mix((c['skin'] ?? src['skin']!), false, 0.5);
  c['SHD'] = _mix((c['skin'] ?? src['skin']!), false, 0.7);
  c['NOSE'] = _mix((c['skin'] ?? src['skin']!), false, 0.4);
  c['MOUTH'] = _mix((c['skin'] ?? src['skin']!), false, 0.65);
  c['HR'] = (c['hair'] ?? src['hair']!);
  c['HRL'] = _mix((c['hair'] ?? src['hair']!), true, 0.4);
  return {for (final e in c.entries) e.key: _hex(e.value)};
}

const String _defs =
    r'<defs><linearGradient id="under" x1="0" x2="1"><stop offset="0" stop-color="#03070A"/><stop offset=".5" stop-color="{UND}"/><stop offset="1" stop-color="#03070A"/></linearGradient><linearGradient id="metal" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{MT0}"/><stop offset=".18" stop-color="{GL}"/><stop offset=".45" stop-color="{MT2}"/><stop offset=".62" stop-color="{MT3}"/><stop offset=".8" stop-color="{MT4}"/><stop offset="1" stop-color="{MT5}"/></linearGradient><linearGradient id="ti" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFF7D6"/><stop offset=".3" stop-color="#E3B341"/><stop offset=".6" stop-color="#6B4A12"/><stop offset=".85" stop-color="#F0CF73"/><stop offset="1" stop-color="#4A3008"/></linearGradient><linearGradient id="cape" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{AN}" stop-opacity=".85"/><stop offset=".6" stop-color="{ACD}" stop-opacity=".45"/><stop offset="1" stop-color="{AN}" stop-opacity=".15"/></linearGradient><linearGradient id="visor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{VS0}"/><stop offset=".5" stop-color="{GL}"/><stop offset="1" stop-color="{VS2}"/></linearGradient><radialGradient id="skin" cx=".4" cy=".35" r=".75"><stop offset="0" stop-color="{SKL}"/><stop offset=".6" stop-color="{SK}"/><stop offset="1" stop-color="{SKD}"/></radialGradient><radialGradient id="aura" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="{GL}" stop-opacity=".38"/><stop offset="1" stop-color="{GL}" stop-opacity="0"/></radialGradient><radialGradient id="bloomA" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="{AN}" stop-opacity=".9"/><stop offset=".45" stop-color="{AN}" stop-opacity=".35"/><stop offset="1" stop-color="{AN}" stop-opacity="0"/></radialGradient><radialGradient id="bloomW" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FFFFFF" stop-opacity="1"/><stop offset=".4" stop-color="#FFFFFF" stop-opacity=".55"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient><radialGradient id="shadow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#000000" stop-opacity=".65"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient><pattern id="hex" width="14" height="12" patternUnits="userSpaceOnUse"><path d="M3.5 0 L10.5 0 L14 6 L10.5 12 L3.5 12 L0 6Z" fill="none" stroke="{HXC}" stroke-width=".7"/></pattern></defs>';

const Map<String, String> _emblems = {
  'atom':
      r'<ellipse rx="9" ry="3.4" fill="none" stroke="{c}" stroke-width="1.6"/><ellipse rx="9" ry="3.4" fill="none" stroke="{c}" stroke-width="1.6" transform="rotate(60)"/><ellipse rx="9" ry="3.4" fill="none" stroke="{c}" stroke-width="1.6" transform="rotate(-60)"/><circle r="2" fill="{c}"/>',
  'bolt': r'<path d="M2 -10 L-6 2 L-1 2 L-3 10 L6 -3 L1 -3Z" fill="{c}"/>',
  'flask':
      r'<path d="M-3 -9 L3 -9 M-2 -9 L-2 -2 L-8 7 C-9 9 -8 10 -6 10 L6 10 C8 10 9 9 8 7 L2 -2 L2 -9" fill="none" stroke="{c}" stroke-width="1.6" stroke-linejoin="round"/><path d="M-6 6 L6 6 L7.4 8.5 L-7.4 8.5Z" fill="{c}"/>',
  'dna':
      r'<path d="M-5 -10 C5 -5 5 5 -5 10 M5 -10 C-5 -5 -5 5 5 10" fill="none" stroke="{c}" stroke-width="1.7"/><path d="M-3 -6 L3 -6 M-4 0 L4 0 M-3 6 L3 6" stroke="{c}" stroke-width="1.3"/>',
  'pi':
      r'<path d="M-8 -6 L8 -6 M-4 -6 C-4 0 -5 6 -7 9 M4 -6 L4 7 C4 9 6 9 8 8" fill="none" stroke="{c}" stroke-width="2.2" stroke-linecap="round"/>',
  'tree':
      r'<circle cy="-3" r="7" fill="{c}"/><rect x="-1.6" y="2" width="3.2" height="8" fill="{c}"/>',
  'hour':
      r'<path d="M-6 -9 L6 -9 L0 0 L6 9 L-6 9 L0 0Z" fill="none" stroke="{c}" stroke-width="1.7" stroke-linejoin="round"/><path d="M-3 6 L3 6 L0 2Z" fill="{c}"/>',
  'compass':
      r'<circle r="9" fill="none" stroke="{c}" stroke-width="1.5"/><path d="M0 -8 L3 0 L0 8 L-3 0Z" fill="{c}"/><circle r="1.6" fill="{bg}"/>',
  'scale':
      r'<path d="M0 -9 L0 8 M-7 -5 L7 -5 M-6 8 L6 8" stroke="{c}" stroke-width="1.6"/><path d="M-7 -5 L-10 2 L-4 2Z M7 -5 L4 2 L10 2Z" fill="{c}"/>',
  'people':
      r'<circle cx="-5" cy="-3" r="3" fill="{c}"/><circle cx="5" cy="-3" r="3" fill="{c}"/><circle cy="-5" r="3.4" fill="{c}"/><path d="M-10 8 C-9 1 9 1 10 8Z" fill="{c}"/>',
  'coin':
      r'<circle r="9" fill="none" stroke="{c}" stroke-width="1.6"/><path d="M-4 -5 L4 -5 M-4 -2 L4 -2 M-3 -5 C3 -5 3 1 -3 1 L3 6" fill="none" stroke="{c}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
  'quill':
      r'<path d="M7 -10 C-4 -6 -6 4 -7 10 C-2 4 4 0 7 -10Z" fill="{c}"/><path d="M-7 10 L-2 3" stroke="{bg}" stroke-width="1"/>',
  'a':
      r'<path d="M-9 -8 L9 -8 M5 -8 L5 9 M0 -1 L5 -1 M-7 -4 C-3 -6 1 -4 -2 -1 C2 0 2 6 -3 6 C-6 6 -8 4 -8 2" fill="none" stroke="{c}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  'bubble':
      r'<path d="M-9 -7 L9 -7 L9 4 L-1 4 L-5 9 L-5 4 L-9 4Z" fill="{c}"/><circle cx="-4" cy="-1.5" r="1.4" fill="{bg}"/><circle cy="-1.5" r="1.4" fill="{bg}"/><circle cx="4" cy="-1.5" r="1.4" fill="{bg}"/>',
  'scroll':
      r'<rect x="-8" y="-7" width="16" height="14" rx="2" fill="none" stroke="{c}" stroke-width="1.6"/><path d="M-5 -3 L5 -3 M-5 1 L5 1 M-5 4 L2 4" stroke="{c}" stroke-width="1.2"/>',
  'code':
      r'<path d="M-4 -6 L-10 0 L-4 6 M4 -6 L10 0 L4 6 M2 -8 L-2 8" fill="none" stroke="{c}" stroke-width="1.8" stroke-linecap="round"/>',
  'book':
      r'<path d="M0 -6 C-4 -9 -9 -8 -10 -7 L-10 8 C-8 6 -4 6 0 9 C4 6 8 6 10 8 L10 -7 C9 -8 4 -9 0 -6Z M0 -6 L0 9" fill="none" stroke="{c}" stroke-width="1.5"/>',
};

const Map<String, String> _masks = {
  'visor': r'M90 62 C100 56 140 56 150 62 L148 78 C138 82 102 82 92 78Z',
  'goggle': r'M95 62 L145 62 A9 9 0 0 1 145 80 L95 80 A9 9 0 0 1 95 62Z',
  'leaf':
      r'M84 66 C96 54 112 58 120 66 C128 58 144 54 156 66 C148 82 130 84 120 76 C110 84 92 82 84 66Z',
  'star':
      r'M86 64 L98 60 L108 64 L120 60 L132 64 L142 60 L154 64 L150 80 L130 80 L120 74 L110 80 L90 80Z',
  'wing':
      r'M78 58 C90 62 100 60 120 66 C140 60 150 62 162 58 C156 74 142 84 120 76 C98 84 84 74 78 58Z',
  'domino':
      r'M90 70 C94 58 112 58 120 66 C128 58 146 58 150 70 C148 82 130 84 120 76 C110 84 92 82 90 70Z',
};

class _Chunk {
  final String layer;
  final bool Function(int t, bool girl) on;
  final String svg;
  const _Chunk(this.layer, this.on, this.svg);
}

final List<_Chunk> _chunks = [
  _Chunk('aura', (t, girl) => t >= 4,
      r'<ellipse cx="200" cy="320" rx="180" ry="270" fill="url(#aura)"/><circle cx="200" cy="300" r="170" fill="none" stroke="{GL}" stroke-width="1.2" stroke-dasharray="2 14" opacity=".6"/><circle cx="200" cy="300" r="150" fill="none" stroke="{AN}" stroke-width=".9" stroke-dasharray="40 30 4 30" opacity=".55"/>'),
  _Chunk('ground', (t, girl) => true,
      r'<ellipse cx="200" cy="548" rx="110" ry="14" fill="url(#shadow)"/>'),
  _Chunk('ground', (t, girl) => t >= 1,
      r'<path d="M80 548 A120 14 0 1 0 320 548 A120 14 0 1 0 80 548" stroke="{GL}" stroke-width="6.4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M80 548 A120 14 0 1 0 320 548 A120 14 0 1 0 80 548" stroke="{GL}" stroke-width="3.52" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M80 548 A120 14 0 1 0 320 548 A120 14 0 1 0 80 548" stroke="{GL}" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
  _Chunk('back', (t, girl) => girl,
      r'<path d="M164 92 Q 148 150 150 236 Q 176 254 200 250 Q 224 254 250 236 Q 252 150 236 92 Z" fill="{HR}"/><path d="M170 120 Q 160 170 164 230 M230 120 Q 240 170 236 230 M184 130 Q 178 180 182 240" stroke="{HRL}" stroke-width="2" fill="none" opacity=".55"/>'),
  _Chunk('back', (t, girl) => girl && t >= 1,
      r'<path d="M164 92 Q 148 150 150 236 M236 92 Q 252 150 250 236" stroke="{GL}" stroke-width="5.6" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M164 92 Q 148 150 150 236 M236 92 Q 252 150 250 236" stroke="{GL}" stroke-width="3.08" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M164 92 Q 148 150 150 236 M236 92 Q 252 150 250 236" stroke="{GL}" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
  _Chunk('cape', (t, girl) => t >= 2,
      r'<path d="M142 180 C 118 262, 92 420, 74 562 Q 110 578 150 566 Q 200 584 250 566 Q 290 578 326 562 C 308 420, 282 262, 258 180 Z" fill="url(#cape)"/><path d="M142 180 C 118 262, 92 420, 74 562 Q 110 578 150 566 Q 200 584 250 566 Q 290 578 326 562 C 308 420, 282 262, 258 180 Z" fill="url(#hex)" opacity=".35"/><path d="M142 180 C 118 262, 92 420, 74 562 Q 110 578 150 566 Q 200 584 250 566 Q 290 578 326 562 C 308 420, 282 262, 258 180 Z" stroke="{AN}" stroke-width="6.4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M142 180 C 118 262, 92 420, 74 562 Q 110 578 150 566 Q 200 584 250 566 Q 290 578 326 562 C 308 420, 282 262, 258 180 Z" stroke="{AN}" stroke-width="3.52" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M142 180 C 118 262, 92 420, 74 562 Q 110 578 150 566 Q 200 584 250 566 Q 290 578 326 562 C 308 420, 282 262, 258 180 Z" stroke="{AN}" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
  _Chunk('body', (t, girl) => !girl,
      r'<path d="M158 300 C 150 360, 140 420, 140 505 L 170 505 C 172 450, 186 380, 200 322 Z" fill="url(#under)"/><path d="M 242 300 C 250 360 260 420 260 505 L 230 505 C 228 450 214 380 200 322 Z" fill="url(#under)"/>'),
  _Chunk('body', (t, girl) => girl,
      r'<path d="M156 300 C 148 360, 142 420, 144 505 L 172 505 C 174 450, 186 380, 200 322 Z" fill="url(#under)"/><path d="M 244 300 C 252 360 258 420 256 505 L 228 505 C 226 450 214 380 200 322 Z" fill="url(#under)"/>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<path d="M160 330 C 156 360, 150 390, 150 404 L 180 404 C 182 386, 190 360, 196 336 Z" fill="url(#metal)" stroke="#020A06"/><path d="M 240 330 C 244 360 250 390 250 404 L 220 404 C 218 386 210 360 204 336 Z" fill="url(#metal)" stroke="#020A06"/>'),
  _Chunk('body', (t, girl) => t >= 4,
      r'<path d="M146 408 L 168 404 L 172 430 L 156 440 L 142 430 Z" fill="url(#ti)"/><path d="M 254 408 L 232 404 L 228 430 L 244 440 L 258 430 Z" fill="url(#ti)"/>'),
  _Chunk('body', (t, girl) => t >= 3,
      r'<path d="M136 448 L 172 448 Q 175 490 176 512 Q 180 528 194 536 Q 198 542 194 546 L 126 546 Q 120 536 126 520 Q 130 490 136 448 Z" fill="url(#metal)" stroke="#020A06"/><path d="M 264 448 L 228 448 Q 225 490 224 512 Q 220 528 206 536 Q 202 542 206 546 L 274 546 Q 280 536 274 520 Q 270 490 264 448 Z" fill="url(#metal)" stroke="#020A06"/>'),
  _Chunk('body', (t, girl) => t < 3,
      r'<path d="M134 470 L 172 470 Q 176 512 178 520 Q 192 530 194 546 L 126 546 Q 122 530 128 512 Z" fill="{TR}" stroke="#020A06"/><path d="M 266 470 L 228 470 Q 224 512 222 520 Q 208 530 206 546 L 274 546 Q 278 530 272 512 Z" fill="{TR}" stroke="#020A06"/><path d="M128 530 L 192 530 M272 530 L 208 530" stroke="{GL}" stroke-width="2" opacity=".8"/>'),
  _Chunk('body', (t, girl) => t >= 4,
      r'<path d="M141 430 L 172 430 L 170 450 L 142 452 Z" fill="url(#ti)"/><path d="M 259 430 L 228 430 L 230 450 L 258 452 Z" fill="url(#ti)"/>'),
  _Chunk('body', (t, girl) => !girl,
      r'<path d="M140 180 Q 200 166 260 180 L 274 200 Q 270 252 246 300 L 154 300 Q 130 252 126 200 Z" fill="url(#under)"/>'),
  _Chunk('body', (t, girl) => girl,
      r'<path d="M146 182 Q 200 170 254 182 L 266 202 Q 258 238 242 266 Q 238 284 246 300 L 154 300 Q 162 284 158 266 Q 142 238 134 202 Z" fill="url(#under)"/>'),
  _Chunk('body', (t, girl) => true,
      r'<path d="M152 312 L 248 312 L 244 334 Q 200 352 156 334 Z" fill="{TR}"/>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<path d="M150 200 C 170 230, 180 260, 178 290 M250 200 C 230 230, 220 260, 222 290 M170 340 C 165 380, 160 420, 156 450 M230 340 C 235 380, 240 420, 244 450 M118 210 C 110 230, 104 250, 104 262 M282 210 C 290 230, 296 250, 296 262" stroke="{GL}" stroke-width="8" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M150 200 C 170 230, 180 260, 178 290 M250 200 C 230 230, 220 260, 222 290 M170 340 C 165 380, 160 420, 156 450 M230 340 C 235 380, 240 420, 244 450 M118 210 C 110 230, 104 250, 104 262 M282 210 C 290 230, 296 250, 296 262" stroke="{GL}" stroke-width="4.4" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M150 200 C 170 230, 180 260, 178 290 M250 200 C 230 230, 220 260, 222 290 M170 340 C 165 380, 160 420, 156 450 M230 340 C 235 380, 240 420, 244 450 M118 210 C 110 230, 104 250, 104 262 M282 210 C 290 230, 296 250, 296 262" stroke="{GL}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
  _Chunk('body', (t, girl) => t >= 1 && !girl,
      r'<path d="M146 186 Q 200 174 254 186 L 262 206 Q 252 238 222 252 L 200 258 L 178 252 Q 148 238 138 206 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1.2"/><path d="M150 212 Q 175 240 200 250 M250 212 Q 225 240 200 250" stroke="#020A06" stroke-width="1.2" fill="none" opacity=".7"/>'),
  _Chunk('body', (t, girl) => t >= 1 && girl,
      r'<path d="M150 188 Q 200 178 250 188 L 258 206 Q 248 236 220 250 L 200 255 L 180 250 Q 152 236 142 206 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1.2"/>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<path d="M156 192 Q 200 182 244 192" stroke="#FFFFFF" stroke-width="2" fill="none" opacity=".6"/>'),
  _Chunk('body', (t, girl) => t >= 1 && !girl,
      r'<path d="M168 262 L232 262 L230 273 L170 273 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1"/><path d="M170 275 L230 275 L228 286 L172 286 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1"/><path d="M172 288 L228 288 L226 299 L174 299 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1"/>'),
  _Chunk('body', (t, girl) => t >= 1 && girl,
      r'<path d="M170 262 L230 262 L228 273 L172 273 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1"/><path d="M172 275 L228 275 L226 286 L174 286 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1"/><path d="M174 288 L226 288 L224 299 L176 299 Z" fill="url(#metal)" stroke="#020A06" stroke-width="1"/>'),
  _Chunk('body', (t, girl) => t >= 2,
      r'<path d="M152 290 L 248 290 L 250 316 L 150 316 Z" fill="url(#ti)"/><rect x="186" y="294" width="28" height="18" rx="4" fill="{TR}" stroke="{GL}" stroke-width="1.5"/><rect x="182" y="290" width="36" height="26" rx="7" fill="none" stroke="{GL}" stroke-width="5" opacity=".25"/>'),
  _Chunk('body', (t, girl) => !girl,
      r'<g transform="translate(0 0)"><path d="M124 188 C 110 214, 99 240, 99 263 L 119 270 C 123 246, 133 226, 144 206 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 1,
      r'<g transform="translate(0 0)"><path d="M99 262 Q 104 284, 140 304 L 154 288 Q 130 272, 119 266 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => !girl && t == 0,
      r'<g transform="translate(0 0)"><path d="M99 262 Q 104 284, 140 304 L 154 288 Q 130 272, 119 266 Z" fill="url(#skin)"/><circle cx="148" cy="296" r="12" fill="url(#skin)" stroke="{SKD}"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 1 && t < 3,
      r'<g transform="translate(0 0)"><circle cx="148" cy="296" r="12" fill="{TR}" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 3,
      r'<g transform="translate(0 0)"><path d="M102 268 Q 112 288 140 304 L 152 290 Q 128 276 118 264 Z" fill="url(#metal)" stroke="#020A06"/><path d="M108 272 L 124 268" stroke="{GL}" stroke-width="8" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M108 272 L 124 268" stroke="{GL}" stroke-width="4.4" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M108 272 L 124 268" stroke="{GL}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="148" cy="296" r="12" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 3 && t < 4,
      r'<g transform="translate(0 0)"><path d="M114 182 Q 140 156 170 172 L 164 210 Q 138 222 110 206 Q 104 190 114 182 Z" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 4,
      r'<g transform="translate(0 0)"><path d="M114 182 Q 140 156 170 172 L 164 210 Q 138 222 110 206 Q 104 190 114 182 Z" fill="url(#ti)" stroke="#2A1A04"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 3,
      r'<g transform="translate(0 0)"><path d="M118 194 L162 188" stroke="{GL}" stroke-width="6.4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M118 194 L162 188" stroke="{GL}" stroke-width="3.52" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M118 194 L162 188" stroke="{GL}" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>'),
  _Chunk('body', (t, girl) => !girl,
      r'<g transform="translate(0 0)"><path d="M 276 188 C 290 214 301 240 301 263 L 281 270 C 277 246 267 226 256 206 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 1,
      r'<g transform="translate(0 0)"><path d="M 301 262 Q 296 284 260 304 L 246 288 Q 270 272 281 266 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => !girl && t == 0,
      r'<g transform="translate(0 0)"><path d="M 301 262 Q 296 284 260 304 L 246 288 Q 270 272 281 266 Z" fill="url(#skin)"/><circle cx="252" cy="296" r="12" fill="url(#skin)" stroke="{SKD}"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 1 && t < 3,
      r'<g transform="translate(0 0)"><circle cx="252" cy="296" r="12" fill="{TR}" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 3,
      r'<g transform="translate(0 0)"><path d="M 298 268 Q 288 288 260 304 L 248 290 Q 272 276 282 264 Z" fill="url(#metal)" stroke="#020A06"/><path d="M292 272 L 276 268" stroke="{GL}" stroke-width="8" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M292 272 L 276 268" stroke="{GL}" stroke-width="4.4" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M292 272 L 276 268" stroke="{GL}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="252" cy="296" r="12" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 3 && t < 4,
      r'<g transform="translate(0 0)"><path d="M 286 182 Q 260 156 230 172 L 236 210 Q 262 222 290 206 Q 296 190 286 182 Z" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 4,
      r'<g transform="translate(0 0)"><path d="M 286 182 Q 260 156 230 172 L 236 210 Q 262 222 290 206 Q 296 190 286 182 Z" fill="url(#ti)" stroke="#2A1A04"/></g>'),
  _Chunk('body', (t, girl) => !girl && t >= 3,
      r'<g transform="translate(0 0)"><path d="M282 194 L238 188" stroke="{GL}" stroke-width="6.4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M282 194 L238 188" stroke="{GL}" stroke-width="3.52" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M282 194 L238 188" stroke="{GL}" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>'),
  _Chunk('body', (t, girl) => girl,
      r'<g transform="translate(5 0)"><path d="M124 188 C 110 214, 99 240, 99 263 L 119 270 C 123 246, 133 226, 144 206 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 1,
      r'<g transform="translate(5 0)"><path d="M99 262 Q 104 284, 140 304 L 154 288 Q 130 272, 119 266 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => girl && t == 0,
      r'<g transform="translate(5 0)"><path d="M99 262 Q 104 284, 140 304 L 154 288 Q 130 272, 119 266 Z" fill="url(#skin)"/><circle cx="148" cy="296" r="12" fill="url(#skin)" stroke="{SKD}"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 1 && t < 3,
      r'<g transform="translate(5 0)"><circle cx="148" cy="296" r="12" fill="{TR}" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 3,
      r'<g transform="translate(5 0)"><path d="M102 268 Q 112 288 140 304 L 152 290 Q 128 276 118 264 Z" fill="url(#metal)" stroke="#020A06"/><path d="M108 272 L 124 268" stroke="{GL}" stroke-width="8" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M108 272 L 124 268" stroke="{GL}" stroke-width="4.4" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M108 272 L 124 268" stroke="{GL}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="148" cy="296" r="12" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 3 && t < 4,
      r'<g transform="translate(5 0)"><path d="M114 182 Q 140 156 170 172 L 164 210 Q 138 222 110 206 Q 104 190 114 182 Z" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 4,
      r'<g transform="translate(5 0)"><path d="M114 182 Q 140 156 170 172 L 164 210 Q 138 222 110 206 Q 104 190 114 182 Z" fill="url(#ti)" stroke="#2A1A04"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 3,
      r'<g transform="translate(5 0)"><path d="M118 194 L162 188" stroke="{GL}" stroke-width="6.4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M118 194 L162 188" stroke="{GL}" stroke-width="3.52" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M118 194 L162 188" stroke="{GL}" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>'),
  _Chunk('body', (t, girl) => girl,
      r'<g transform="translate(-5 0)"><path d="M 276 188 C 290 214 301 240 301 263 L 281 270 C 277 246 267 226 256 206 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 1,
      r'<g transform="translate(-5 0)"><path d="M 301 262 Q 296 284 260 304 L 246 288 Q 270 272 281 266 Z" fill="url(#under)"/></g>'),
  _Chunk('body', (t, girl) => girl && t == 0,
      r'<g transform="translate(-5 0)"><path d="M 301 262 Q 296 284 260 304 L 246 288 Q 270 272 281 266 Z" fill="url(#skin)"/><circle cx="252" cy="296" r="12" fill="url(#skin)" stroke="{SKD}"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 1 && t < 3,
      r'<g transform="translate(-5 0)"><circle cx="252" cy="296" r="12" fill="{TR}" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 3,
      r'<g transform="translate(-5 0)"><path d="M 298 268 Q 288 288 260 304 L 248 290 Q 272 276 282 264 Z" fill="url(#metal)" stroke="#020A06"/><path d="M292 272 L 276 268" stroke="{GL}" stroke-width="8" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M292 272 L 276 268" stroke="{GL}" stroke-width="4.4" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M292 272 L 276 268" stroke="{GL}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="252" cy="296" r="12" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 3 && t < 4,
      r'<g transform="translate(-5 0)"><path d="M 286 182 Q 260 156 230 172 L 236 210 Q 262 222 290 206 Q 296 190 286 182 Z" fill="url(#metal)" stroke="#020A06"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 4,
      r'<g transform="translate(-5 0)"><path d="M 286 182 Q 260 156 230 172 L 236 210 Q 262 222 290 206 Q 296 190 286 182 Z" fill="url(#ti)" stroke="#2A1A04"/></g>'),
  _Chunk('body', (t, girl) => girl && t >= 3,
      r'<g transform="translate(-5 0)"><path d="M282 194 L238 188" stroke="{GL}" stroke-width="6.4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M282 194 L238 188" stroke="{GL}" stroke-width="3.52" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M282 194 L238 188" stroke="{GL}" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>'),
  _Chunk('body', (t, girl) => t == 0,
      r'<path d="M100 262 L 120 268 M300 262 L 280 268" stroke="{AN}" stroke-width="3" stroke-linecap="round"/>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<circle cx="200" cy="222" r="46" fill="url(#bloomA)"/>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<path d="M200 196 L 222 209 L 222 235 L 200 248 L 178 235 L 178 209 Z" fill="{BADGE}" stroke="url(#ti)" stroke-width="3"/><g transform="translate(200 222) scale(1.45)">{EMB}</g>'),
  _Chunk('body', (t, girl) => t == 0,
      r'<circle cx="200" cy="222" r="17" fill="{BADGE}" stroke="{AN}" stroke-width="2.5"/><g transform="translate(200 222) scale(1.05)">{EMB}</g>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<path d="M188 146 L 212 146 L 215 176 Q 200 184 185 176 Z" fill="{UND}"/>'),
  _Chunk('body', (t, girl) => t == 0,
      r'<path d="M188 146 L 212 146 L 215 176 Q 200 184 185 176 Z" fill="url(#skin)"/>'),
  _Chunk('body', (t, girl) => !girl,
      r'<path d="M170 106 Q 170 72 200 70 Q 230 72 230 106 Q 230 138 214 151 Q 200 160 186 151 Q 170 138 170 106 Z" fill="url(#skin)"/>'),
  _Chunk('body', (t, girl) => girl,
      r'<path d="M172 108 Q 172 74 200 72 Q 228 74 228 108 Q 228 136 213 149 Q 200 157 187 149 Q 172 136 172 108 Z" fill="url(#skin)"/>'),
  _Chunk('body', (t, girl) => true,
      r'<path d="M220 96 Q 230 116 220 140 Q 214 150 206 152" stroke="{SHD}" stroke-width="6" fill="none" opacity=".22" stroke-linecap="round"/><path d="M199 120 Q 196 130 200 134 Q 204 135 206 132" stroke="{NOSE}" stroke-width="1.5" fill="none"/>'),
  _Chunk('body', (t, girl) => !girl,
      r'<path d="M188 141 Q 200 147 212 141" stroke="{MOUTH}" stroke-width="2.2" fill="none" stroke-linecap="round"/>'),
  _Chunk('body', (t, girl) => girl,
      r'<path d="M190 138 Q 200 145 210 138" stroke="{MOUTH}" stroke-width="2.2" fill="none" stroke-linecap="round"/>'),
  _Chunk('body', (t, girl) => !girl,
      r'<path d="M163 112 Q 150 70 178 50 Q 206 34 234 50 Q 252 68 238 108 Q 234 92 226 86 Q 232 74 218 70 Q 216 82 204 84 Q 198 72 186 76 Q 188 86 178 90 Q 168 98 163 112 Z" fill="{HR}"/><path d="M176 58 Q 200 44 228 56 M170 76 Q 184 60 204 58" stroke="{HRL}" stroke-width="1.4" fill="none" opacity=".6"/>'),
  _Chunk('body', (t, girl) => girl,
      r'<path d="M168 112 Q 158 66 200 58 Q 242 66 232 112 Q 230 92 218 84 Q 206 96 186 92 Q 176 98 168 112 Z" fill="{HR}"/><path d="M176 70 Q 200 60 224 70" stroke="{HRL}" stroke-width="2" fill="none" opacity=".6"/><path d="M172 104 Q 160 150 164 214 Q 170 222 176 214 Q 174 160 182 118 Z" fill="{HR}"/><path d="M228 104 Q 240 150 236 214 Q 230 222 224 214 Q 226 160 218 118 Z" fill="{HR}"/>'),
  _Chunk('body', (t, girl) => girl && t >= 1,
      r'<path d="M168 130 Q 162 170 166 210 M232 130 Q 238 170 234 210" stroke="{GL}" stroke-width="1.4" fill="none" opacity=".7"/>'),
  _Chunk('body', (t, girl) => t == 0,
      r'<path d="M178 100 Q 186 96 195 100 M205 100 Q 214 96 222 100" stroke="{HR}" stroke-width="2.6" fill="none" stroke-linecap="round"/>'),
  _Chunk('body', (t, girl) => t >= 4,
      r'<path d="M162 100 Q 200 72 238 100 L 240 108 Q 200 84 160 108 Z" fill="url(#ti)"/><path d="M200 64 L 208 82 L 200 92 L 192 82 Z" fill="{GL}"/><path d="M200 60 L 212 82 L 200 96 L 188 82 Z" fill="{GL}" opacity=".25"/>'),
  _Chunk('body', (t, girl) => t >= 1,
      r'<path d="{MASK}" transform="translate(200 113) scale(1.08) translate(-120 -70)" fill="none" stroke="{GL}" stroke-width="9" opacity=".18"/><path d="{MASK}" transform="translate(200 113) scale(1.08) translate(-120 -70)" fill="none" stroke="{GL}" stroke-width="4" opacity=".35"/><path d="{MASK}" transform="translate(200 113) scale(1.08) translate(-120 -70)" fill="url(#visor)"/>'),
  _Chunk('body', (t, girl) => girl && t >= 1,
      r'<path d="M174 110 L 171 106 M178 108 L 176 104 M226 110 L 229 106 M222 108 L 224 104" stroke="#111111" stroke-width="1.4" stroke-linecap="round"/>'),
  _Chunk('glow', (t, girl) => t >= 1,
      r'<path d="M150 200 C 170 230, 180 260, 178 290 M250 200 C 230 230, 220 260, 222 290 M170 340 C 165 380, 160 420, 156 450 M230 340 C 235 380, 240 420, 244 450 M118 210 C 110 230, 104 250, 104 262 M282 210 C 290 230, 296 250, 296 262" stroke="#FFFFFF" stroke-width="4" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M150 200 C 170 230, 180 260, 178 290 M250 200 C 230 230, 220 260, 222 290 M170 340 C 165 380, 160 420, 156 450 M230 340 C 235 380, 240 420, 244 450 M118 210 C 110 230, 104 250, 104 262 M282 210 C 290 230, 296 250, 296 262" stroke="#FFFFFF" stroke-width="2.2" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M150 200 C 170 230, 180 260, 178 290 M250 200 C 230 230, 220 260, 222 290 M170 340 C 165 380, 160 420, 156 450 M230 340 C 235 380, 240 420, 244 450 M118 210 C 110 230, 104 250, 104 262 M282 210 C 290 230, 296 250, 296 262" stroke="#FFFFFF" stroke-width="1" fill="none" stroke-linecap="round" stroke-linejoin="round"/><circle cx="200" cy="222" r="30" fill="url(#bloomA)"/>'),
  _Chunk('eyes', (t, girl) => t >= 1,
      r'<path d="M175 113 Q 186 107 196 114 Q 186 118 175 113 Z" fill="#FFFFFF"/><path d="M225 113 Q 214 107 204 114 Q 214 118 225 113 Z" fill="#FFFFFF"/>'),
  _Chunk('eyes', (t, girl) => t == 0,
      r'<ellipse cx="186" cy="113" rx="8" ry="5" fill="#FFFFFF"/><ellipse cx="214" cy="113" rx="8" ry="5" fill="#FFFFFF"/><circle cx="187" cy="113" r="3.4" fill="#3B2412"/><circle cx="213" cy="113" r="3.4" fill="#3B2412"/><circle cx="188.2" cy="111.8" r="1.2" fill="#FFFFFF"/><circle cx="214.2" cy="111.8" r="1.2" fill="#FFFFFF"/>'),
  _Chunk('eyes', (t, girl) => girl && t == 0,
      r'<path d="M178 109 L 175 105 M182 108 L 180 104 M222 109 L 225 105 M218 108 L 220 104" stroke="#111111" stroke-width="1.4" stroke-linecap="round"/>'),
  _Chunk('flash', (t, girl) => true,
      r'<circle cx="200" cy="222" r="70" fill="url(#bloomW)"/>'),
  _Chunk('shock', (t, girl) => true,
      r'<path d="M166 222 A34 34 0 1 0 234 222 A34 34 0 1 0 166 222" stroke="{AN}" stroke-width="12.8" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M166 222 A34 34 0 1 0 234 222 A34 34 0 1 0 166 222" stroke="{AN}" stroke-width="7.04" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M166 222 A34 34 0 1 0 234 222 A34 34 0 1 0 166 222" stroke="{AN}" stroke-width="3.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
  _Chunk('shock2', (t, girl) => true,
      r'<path d="M166 222 A34 34 0 1 0 234 222 A34 34 0 1 0 166 222" stroke="{GL}" stroke-width="9.6" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M166 222 A34 34 0 1 0 234 222 A34 34 0 1 0 166 222" stroke="{GL}" stroke-width="5.28" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M166 222 A34 34 0 1 0 234 222 A34 34 0 1 0 166 222" stroke="{GL}" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
  _Chunk('sparks', (t, girl) => true,
      r'<path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{GL}" transform="translate(270.0 222.0) rotate(90) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{AN}" transform="translate(256.6 263.1) rotate(126) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{GL}" transform="translate(221.6 288.6) rotate(162) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{AN}" transform="translate(178.4 288.6) rotate(198) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{GL}" transform="translate(143.4 263.1) rotate(234) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{AN}" transform="translate(130.0 222.0) rotate(270) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{GL}" transform="translate(143.4 180.9) rotate(306) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{AN}" transform="translate(178.4 155.4) rotate(342) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{GL}" transform="translate(221.6 155.4) rotate(378) scale(1.6)"/><path d="M0 -6 L2 0 L0 6 L-2 0Z" fill="{AN}" transform="translate(256.6 180.8) rotate(414) scale(1.6)"/>'),
  _Chunk('vflare', (t, girl) => true,
      r'<ellipse cx="200" cy="113" rx="60" ry="18" fill="url(#bloomW)"/>'),
  _Chunk('impact', (t, girl) => true,
      r'<path d="M90 548 A110 16 0 1 0 310 548 A110 16 0 1 0 90 548" stroke="{AN}" stroke-width="14" fill="none" opacity="0.12" stroke-linecap="round" stroke-linejoin="round"/><path d="M90 548 A110 16 0 1 0 310 548 A110 16 0 1 0 90 548" stroke="{AN}" stroke-width="7.7" fill="none" opacity="0.28" stroke-linecap="round" stroke-linejoin="round"/><path d="M90 548 A110 16 0 1 0 310 548 A110 16 0 1 0 90 548" stroke="{AN}" stroke-width="3.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
];

final RegExp _tok = RegExp(r'\{([A-Z0-9]+)\}');

/// [girl]: girl version; [level]: costume level 0..4.
BiotechLayers buildBiotechLayers(HeroDef h,
    {required bool girl, required int level}) {
  final t = level.clamp(0, 4);
  final v = _tokens(h);
  v['EMB'] = (_emblems[h.emblem] ?? _emblems['book']!)
      .replaceAll('{c}', v['ACL']!)
      .replaceAll('{bg}', v['BADGE']!);
  v['MASK'] = _masks[h.mask] ?? _masks['domino']!;
  String layer(String name) {
    final b = StringBuffer();
    for (final c in _chunks) {
      if (c.layer == name && c.on(t, girl)) b.write(c.svg);
    }
    if (b.isEmpty) return '';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">$_defs$b</svg>'
        .replaceAllMapped(_tok, (m) => v[m[1]] ?? m[0]!);
  }

  return BiotechLayers(
    aura: layer('aura'),
    ground: layer('ground'),
    back: layer('back'),
    cape: layer('cape'),
    body: layer('body'),
    glow: layer('glow'),
    eyes: layer('eyes'),
    flash: layer('flash'),
    shock: layer('shock'),
    shock2: layer('shock2'),
    sparks: layer('sparks'),
    vflare: layer('vflare'),
    impact: layer('impact'),
  );
}
