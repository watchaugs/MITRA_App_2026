'use strict';
// Which writing system each language pack uses, and a check for letters from
// another one (machine translation sometimes drops an Urdu or Hindi word into a
// Santali or Manipuri sentence). Latin letters are always allowed (MITRA, AR,
// XP, OTP …). Used by translate_missing.js and fix_pack_values.js.

const RANGES = {
  devanagari: /[ऀ-ॿ]/,
  bengali: /[ঀ-৿]/,
  gurmukhi: /[਀-੿]/,
  gujarati: /[઀-૿]/,
  oriya: /[଀-୿]/,
  tamil: /[஀-௿]/,
  telugu: /[ఀ-౿]/,
  kannada: /[ಀ-೿]/,
  malayalam: /[ഀ-ൿ]/,
  meetei: /[ꫠ-꫿ꯀ-꯿]/,
  olchiki: /[᱐-᱿]/,
  arabic: /[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]/,
};

const SCRIPT_OF = {
  hi: 'devanagari', mr: 'devanagari', ne: 'devanagari', sa: 'devanagari', mai: 'devanagari',
  doi: 'devanagari', brx: 'devanagari', kok: 'devanagari',
  as: 'bengali', bn: 'bengali', pa: 'gurmukhi', gu: 'gujarati', or: 'oriya', ta: 'tamil',
  te: 'telugu', kn: 'kannada', ml: 'malayalam', mni: 'meetei', sat: 'olchiki',
  ur: 'arabic', ks: 'arabic', sd: 'arabic',
};

/**
 * Letters in `text` that belong to a writing system other than the language's
 * own (and not Latin). Returns '' when the text is clean or the language is
 * unknown. Punctuation, digits and marks are ignored.
 */
function foreignLetters(lang, text) {
  const own = RANGES[SCRIPT_OF[lang]];
  if (!own) return '';
  let out = '';
  for (const ch of String(text || '')) {
    if (!/\p{L}/u.test(ch) || /[A-Za-z]/.test(ch) || own.test(ch)) continue;
    if (Object.values(RANGES).some(r => r.test(ch))) out += ch;
  }
  return out;
}

module.exports = { foreignLetters, SCRIPT_OF };
