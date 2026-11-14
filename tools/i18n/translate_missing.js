#!/usr/bin/env node
'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// Fill missing UI strings in assets/locales/<lang>.json using Bhashini NMT.
//
//   Run from the app repo root (needs Node 18+, no npm install):
//     $env:BHASHINI_USER_ID = "<from dashboard .env>"
//     $env:BHASHINI_API_KEY = "<from dashboard .env>"
//     node tools/i18n/translate_missing.js            # all languages
//     node tools/i18n/translate_missing.js hi ta      # only these
//     node tools/i18n/translate_missing.js --dry-run  # count, no API calls
//
// Safe by design:
//  • Only keys present in en.json but MISSING from a pack are translated, so a
//    rerun resumes where it stopped and never touches reviewed translations.
//  • {placeholders} and protected terms (MITRA, DPDPA) are swapped for numeric
//    tokens before translation and restored after. If a result comes back with
//    any token missing or altered, it is NOT saved — the app then shows English
//    for that string (tr() falls back), and the key is listed at the end.
//  • Konkani (kok) is skipped: the Bhashini pipeline rejects it (HTTP 400).
//  • Each pack is written after its language finishes.
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');

const DIR = path.join(process.cwd(), 'assets', 'locales');
const CONFIG_URL = process.env.BHASHINI_CONFIG_URL ||
  'https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline';
const PIPELINE_ID = process.env.BHASHINI_PIPELINE_ID || '64392f96daac500b55c543cd';
const ALL_LANGS = ['as', 'bn', 'brx', 'doi', 'gu', 'hi', 'kn', 'ks', 'mai', 'ml', 'mni',
  'mr', 'ne', 'or', 'pa', 'sa', 'sat', 'sd', 'ta', 'te', 'ur'];   // kok skipped
const PROTECTED_TERMS = ['MITRA', 'DPDPA'];
const BATCH = 16;

const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const only = args.filter(a => !a.startsWith('--'));
const LANGS = only.length ? ALL_LANGS.filter(l => only.includes(l)) : ALL_LANGS;

function readPack(lang) {
  const p = path.join(DIR, lang + '.json');
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}
function writePack(lang, obj) {
  fs.writeFileSync(path.join(DIR, lang + '.json'), JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

// {name} and protected terms -> {0},{1}… ; returns [maskedText, tokens[]]
function mask(text) {
  const tokens = [];
  let s = text.replace(/\{[A-Za-z_][\w]*\}/g, m => `{${tokens.push(m) - 1}}`);
  for (const term of PROTECTED_TERMS) {
    s = s.replace(new RegExp(`\\b${term}\\b`, 'g'), () => `{${tokens.push(term) - 1}}`);
  }
  return [s, tokens];
}
function unmask(text, tokens) {
  const found = (text.match(/\{\d+\}/g) || []).map(t => Number(t.slice(1, -1)));
  const expected = tokens.map((_, i) => i);
  const ok = found.length === expected.length &&
    [...found].sort((a, b) => a - b).every((v, i) => v === expected[i]);
  if (!ok) return null;
  return text.replace(/\{(\d+)\}/g, (_, i) => tokens[Number(i)]);
}

const cfgCache = new Map();
async function getConfig(src, tgt) {
  const key = `${src}:${tgt}`;
  if (cfgCache.has(key)) return cfgCache.get(key);
  const res = await fetch(CONFIG_URL, {
    method: 'POST',
    headers: { userID: process.env.BHASHINI_USER_ID, ulcaApiKey: process.env.BHASHINI_API_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pipelineTasks: [{ taskType: 'translation', config: { language: { sourceLanguage: src, targetLanguage: tgt } } }],
      pipelineRequestConfig: { pipelineId: PIPELINE_ID },
    }),
  });
  if (!res.ok) throw new Error(`config ${tgt}: HTTP ${res.status}`);
  const d = await res.json();
  const ep = d.pipelineInferenceAPIEndPoint;
  const taskCfg = (d.pipelineResponseConfig || []).find(p => p.taskType === 'translation');
  const cfg = { url: ep.callbackUrl, authKey: ep.inferenceApiKey?.name, authVal: ep.inferenceApiKey?.value,
    serviceId: taskCfg?.config?.[0]?.serviceId };
  cfgCache.set(key, cfg);
  return cfg;
}
async function translateBatch(texts, tgt) {
  const cfg = await getConfig('en', tgt);
  const res = await fetch(cfg.url, {
    method: 'POST',
    headers: { [cfg.authKey]: cfg.authVal, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pipelineTasks: [{ taskType: 'translation',
        config: { language: { sourceLanguage: 'en', targetLanguage: tgt }, serviceId: cfg.serviceId } }],
      inputData: { input: texts.map(source => ({ source })) },
    }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const d = await res.json();
  const out = d?.pipelineResponse?.find(p => p.taskType === 'translation')?.output || [];
  if (out.length !== texts.length) throw new Error(`expected ${texts.length} results, got ${out.length}`);
  return out.map(o => o?.target ?? '');
}

(async () => {
  if (!DRY && !(process.env.BHASHINI_USER_ID && process.env.BHASHINI_API_KEY)) {
    console.error('Set BHASHINI_USER_ID and BHASHINI_API_KEY first (values from the dashboard .env).');
    process.exit(1);
  }
  const en = readPack('en');
  const keepEnglish = [];
  let total = 0;
  for (const lang of LANGS) {
    const pack = readPack(lang);
    const todo = Object.keys(en).filter(k => !(k in pack) && /[A-Za-z]{2,}/.test(String(en[k])));
    total += todo.length;
    if (DRY || todo.length === 0) { console.log(`${lang}.json: ${todo.length} to translate`); continue; }
    let done = 0;
    for (let i = 0; i < todo.length; i += BATCH) {
      const keys = todo.slice(i, i + BATCH);
      const masked = keys.map(k => mask(String(en[k])));
      let results;
      try {
        results = await translateBatch(masked.map(m => m[0]), lang);
      } catch (e) {
        // batch failed — retry one by one so a single bad string can't sink the rest
        results = [];
        for (const m of masked) {
          try { results.push((await translateBatch([m[0]], lang))[0]); }
          catch (e2) { results.push(null); }
        }
      }
      keys.forEach((k, j) => {
        const r = results[j];
        const restored = r && r.trim() ? unmask(r.trim(), masked[j][1]) : null;
        if (restored && restored !== en[k]) { pack[k] = restored; done++; }
        else keepEnglish.push(`${lang}/${k}`);
      });
    }
    writePack(lang, pack);
    console.log(`${lang}.json: translated ${done} of ${todo.length}`);
  }
  if (DRY) console.log(`total to translate: ${total}`);
  if (keepEnglish.length) {
    console.log(`\n${keepEnglish.length} string(s) left in English (failed or placeholder check). Rerun to retry:`);
    console.log('  ' + keepEnglish.slice(0, 40).join('\n  ') + (keepEnglish.length > 40 ? '\n  …' : ''));
  }
  console.log('done');
})().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
