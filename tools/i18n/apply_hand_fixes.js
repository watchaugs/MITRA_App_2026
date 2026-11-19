#!/usr/bin/env node
'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// Writes the hand-checked strings in tools/i18n/hand_fixes.json into
// assets/locales/<lang>.json (adds new keys, replaces existing values).
// translate_missing.js never overwrites these keys afterwards.
//
//   Run from the app repo root:   node tools/i18n/apply_hand_fixes.js
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');

const DIR = path.join(process.cwd(), 'assets', 'locales');
const fixes = JSON.parse(fs.readFileSync(path.join(__dirname, 'hand_fixes.json'), 'utf8'));

let changed = 0;
for (const [lang, vals] of Object.entries(fixes)) {
  if (lang.startsWith('_')) continue;
  const file = path.join(DIR, lang + '.json');
  const pack = JSON.parse(fs.readFileSync(file, 'utf8'));
  let n = 0;
  for (const [k, v] of Object.entries(vals)) {
    if (pack[k] !== v) { pack[k] = v; n++; }
  }
  if (n) {
    fs.writeFileSync(file, JSON.stringify(pack, null, 2) + '\n', 'utf8');
    console.log(`${lang}.json: ${n} value(s) set`);
    changed += n;
  } else {
    console.log(`${lang}.json: already up to date`);
  }
}
console.log(`done — ${changed} change(s)`);
