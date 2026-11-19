#!/usr/bin/env node
'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// Reads the corrected review sheet (CSV, UTF-8) and stores every changed cell
// in tools/i18n/hand_fixes.json, so it is locked against machine translation.
// Then run apply_hand_fixes.js to write the values into the language packs.
//
//   node tools/i18n/import_review.js [path/to/translations_review.csv]
//   node tools/i18n/apply_hand_fixes.js
//
// A cell is skipped (and listed) if its {placeholders} differ from English.
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');

const DIR = path.join(process.cwd(), 'assets', 'locales');
const HF = path.join(__dirname, 'hand_fixes.json');
const file = process.argv[2] || path.join(__dirname, 'review', 'translations_review.csv');

// Minimal CSV parser: quotes, doubled quotes, commas and newlines in cells.
function parseCsv(text) {
  const rows = []; let row = []; let cell = ''; let q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') q = false;
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cell); rows.push(row); row = []; cell = '';
    } else cell += c;
  }
  if (cell !== '' || row.length) { row.push(cell); rows.push(row); }
  return rows.filter(r => r.some(x => x !== ''));
}

const read = l => {
  try { return JSON.parse(fs.readFileSync(path.join(DIR, l + '.json'), 'utf8')); } catch (_) { return {}; }
};
const ph = s => (String(s).match(/\{\w+\}/g) || []).sort().join('|');

const rows = parseCsv(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
const [header, ...data] = rows;
const langs = header.slice(2);
const en = read('en');
const packs = Object.fromEntries(langs.map(l => [l, read(l)]));
const hf = fs.existsSync(HF) ? JSON.parse(fs.readFileSync(HF, 'utf8')) : {};

let added = 0; const skipped = [];
for (const r of data) {
  const key = r[0];
  if (!key || !(key in en)) continue;
  langs.forEach((l, i) => {
    const v = (r[i + 2] ?? '').trim();
    if (!v || v === packs[l][key]) return; // empty or unchanged
    if (ph(v) !== ph(en[key])) { skipped.push(`${l}/${key}`); return; }
    hf[l] = hf[l] || {};
    if (hf[l][key] !== v) { hf[l][key] = v; added++; }
  });
}
fs.writeFileSync(HF, JSON.stringify(hf, null, 2) + '\n', 'utf8');
console.log(`${added} corrected value(s) saved to hand_fixes.json`);
if (skipped.length) {
  console.log(`Skipped (placeholders like {n} changed — fix the cell and rerun):`);
  skipped.forEach(s => console.log('  ' + s));
}
console.log('Next: node tools/i18n/apply_hand_fixes.js');
