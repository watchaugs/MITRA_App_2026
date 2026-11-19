#!/usr/bin/env node
'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// One-time repair. Round 3 of fix_pack_values.js joined "X 'Y" into "X'Y" in
// every pack. That is right for Assamese (ল'ড, হ'ব) and Dogri (र'वो), but wrong
// for:
//   • Punjabi  — 'ਤੇ / 'ਚ are separate short words:   ਫੋਨ'ਤੇ  → ਫੋਨ 'ਤੇ
//   • Santali  — quotes around a term:                  ᱜᱮ'AR'  → ᱜᱮ 'AR'
//   • Bodo     — cannot tell a joined word from two words, so the text goes
//                back to exactly what Bhashini returned:  हिर'कार्ड → हिर 'कार्ड
//   • Assamese — "video" ends in ': ভিডিঅ'অটোপ্লে → ভিডিঅ' অটোপ্লে
// fix_pack_values.js now joins only in Assamese and Dogri, so this does not
// come back. Safe to run more than once.
//
//   Run from the app repo root:   node tools/i18n/undo_apostrophe_join.js
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');

const DIR = path.join(process.cwd(), 'assets', 'locales');
const RULES = {
  pa: [[/([\p{L}\p{M}])'(ਤੇ|ਚ)(?=[\s,.!?।]|$)/gu, "$1 '$2"]],
  sat: [[/([᱐-᱿])'(?=[A-Za-z])/gu, "$1 '"]],
  brx: [[/([ऀ-ॣ०-ॿ])'(?=[ऀ-ॣ०-ॿ])/gu, "$1 '"]],
  as: [[/ভিডিঅ'(?!টো)(?=[\p{L}])/gu, "ভিডিঅ' "]],
};

let total = 0;
for (const [lang, rules] of Object.entries(RULES)) {
  const file = path.join(DIR, `${lang}.json`);
  if (!fs.existsSync(file)) continue;
  const pack = JSON.parse(fs.readFileSync(file, 'utf8'));
  let n = 0;
  for (const k of Object.keys(pack)) {
    if (typeof pack[k] !== 'string') continue;
    let v = pack[k];
    for (const [re, to] of rules) v = v.replace(re, to);
    if (v !== pack[k]) { pack[k] = v; n++; }
  }
  if (n) fs.writeFileSync(file, JSON.stringify(pack, null, 2) + '\n', 'utf8');
  console.log(`${lang}.json: ${n} value(s) restored`);
  total += n;
}
console.log(`done — ${total} change(s)`);
