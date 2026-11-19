#!/usr/bin/env node
'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// Writes a review sheet of the strings that machine translation tends to get
// wrong (hand-fixed in Hindi, reworded for Bhashini, anything with "AR" or
// "hero", subject names) — one row per string, one column per language.
// Open it in Excel / Google Sheets, let a native speaker correct the cells,
// save as CSV (UTF-8), then run import_review.js.
//
//   node tools/i18n/export_review.js
//   → tools/i18n/review/translations_review.csv
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');

const DIR = path.join(process.cwd(), 'assets', 'locales');
const OUT_DIR = path.join(__dirname, 'review');
const LANGS = ['hi', 'as', 'bn', 'brx', 'doi', 'gu', 'kn', 'kok', 'ks', 'mai', 'ml', 'mni',
  'mr', 'ne', 'or', 'pa', 'sa', 'sat', 'sd', 'ta', 'te', 'ur'];

const read = l => {
  try { return JSON.parse(fs.readFileSync(path.join(DIR, l + '.json'), 'utf8')); } catch (_) { return {}; }
};
const en = read('en');

const keys = new Set();
try {
  const hf = JSON.parse(fs.readFileSync(path.join(__dirname, 'hand_fixes.json'), 'utf8'));
  Object.keys(hf.hi || {}).forEach(k => keys.add(k));
} catch (_) {}
try {
  const src = fs.readFileSync(path.join(__dirname, 'translate_missing.js'), 'utf8');
  const block = src.slice(src.indexOf('const SOURCE_OVERRIDES'), src.indexOf('// Reviewed by hand'));
  for (const m of block.matchAll(/^\s+(\w+):\s/gm)) keys.add(m[1]);
} catch (_) {}
for (const [k, v] of Object.entries(en)) {
  if (typeof v === 'string' && (/\bAR/.test(v) || /hero/i.test(v))) keys.add(k);
}

const packs = Object.fromEntries(LANGS.map(l => [l, read(l)]));
const cell = v => {
  const s = v == null ? '' : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const rows = [['key', 'English', ...LANGS].join(',')];
for (const k of [...keys].filter(k => k in en).sort()) {
  rows.push([k, en[k], ...LANGS.map(l => packs[l][k] ?? '')].map(cell).join(','));
}
fs.mkdirSync(OUT_DIR, { recursive: true });
const out = path.join(OUT_DIR, 'translations_review.csv');
fs.writeFileSync(out, '﻿' + rows.join('\r\n') + '\r\n', 'utf8'); // BOM: Excel reads UTF-8
console.log(`${rows.length - 1} strings → ${path.relative(process.cwd(), out)}`);
