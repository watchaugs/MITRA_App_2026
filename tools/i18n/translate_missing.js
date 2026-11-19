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
//  • SOURCE_OVERRIDES: for these keys Bhashini translates the given English
//    phrase instead of the en.json text (the on-screen English stays as is).
//  • --redo=key1,key2 retranslates those keys even where a pack has them
//    (to replace bad translations). HAND_SET keys are never overwritten.
//       node tools/i18n/translate_missing.js --redo=student_thought_for_the_day,student_brain_spark
//  • --redo-overrides retranslates every key in SOURCE_OVERRIDES.
//  • --redo-term=AR retranslates every key whose English contains that word
//    (used to keep "AR" as "AR" in all languages).
//  • Values in tools/i18n/hand_fixes.json are hand-checked and locked too.
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');
const { foreignLetters } = require('./script_check');

const DIR = path.join(process.cwd(), 'assets', 'locales');
const CONFIG_URL = process.env.BHASHINI_CONFIG_URL ||
  'https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline';
const PIPELINE_ID = process.env.BHASHINI_PIPELINE_ID || '64392f96daac500b55c543cd';
const ALL_LANGS = ['as', 'bn', 'brx', 'doi', 'gu', 'hi', 'kn', 'ks', 'mai', 'ml', 'mni',
  'mr', 'ne', 'or', 'pa', 'sa', 'sat', 'sd', 'ta', 'te', 'ur'];   // kok skipped
// Never translated or transliterated (stay exactly as written).
// OTP and XP stay in Latin letters, as in the Hindi pack ("OTP भेजें", "XP").
const PROTECTED_TERMS = ['MITRA', 'DPDPA', 'ARCore', 'AR', 'OTP', 'XP'];
const BATCH = 16;

// Translate these keys from a plainer English phrase (literal "Thought for
// the day" / "Brain Spark" came back meaningless).
const SOURCE_OVERRIDES = {
  student_thought_for_the_day: "Today's wise thought",
  student_brain_spark: 'Fun Fact',
  // Short or ambiguous English that came back mangled ("power" → electricity,
  // "h"/"m" → letters/metres, "streak" → line, "order" → purchase order).
  fun_power_next: '{left} more days until strength level {next}',
  student_next_fact_in_hoursleft_h_minsleft: 'Next fact in {hoursLeft} hours {minsLeft} minutes',
  student_next_fact_in_minsleft_m: 'Next fact in {minsLeft} minutes',
  student_minutes_ago: '{n} minutes ago',
  student_hours_ago: '{n} hours ago',
  student_days_ago: '{n} days ago',
  student_streakdays_streak: '🔥 {streakDays} days in a row',
  quiz_streak_streak: '🔥 {streak} days in a row',
  student_qs: 'Questions',
  student_avg_v1: 'average {v1}%',
  student_mastered_pct: 'Mastered {pct}%',
  quiz_seq_ready: 'All set! Now check your sequence.',
  quiz_seq_check: 'Check my sequence',
  ar_keep_page_in_view: 'Keep the page in front of the camera',
  // "Class" alone came back as category/type, not school class.
  auth_class_number: 'School class {number}',
  settings_change_class: 'Change school class',
  student_select_class: 'Select school class',
  settings_tap_to_select_a_new_class: 'Tap to select a new school class',
  teacher_class_average: 'School class average',
  // Short English that came back with the wrong meaning or word order.
  auth_mobile_belongs_to: 'This mobile phone belongs to',
  auth_resend_in_resendtimer_s: 'Resend in {resendTimer} seconds',
  student_remaining_xp_to_title: '{remaining} more XP to reach {title}',
  fun_hq_rank_next: '{xp} XP · {left} more XP to reach {rank}',
  fun_hq_cards_sub: '{got} out of {all} collected',
  fun_album_title: 'Hero cards · {got} out of {all}',
  student_day_streak: 'Days in a row',
  student_day_streak_2: 'Days in a row',
  fun_parent_streak: 'days in a row',
  student_quiz_unlocked: 'The quiz is now open',
  terr_unsaved_title: 'Only saved lessons',
  fun_goal_loading: 'Your missions are getting ready…',
  quiz_read_explanation_to_continue: 'Read the explanation to continue…',
  teacher_assign: 'Assign to class',
  teacher_push_lessons_quizzes_to_your: 'Send lessons and quizzes to your class',
  fun_costume_full: 'Full costume ready — a true Gyani hero!',
};
// Reviewed by hand — never replaced by machine translation.
const HAND_SET = {
  hi: ['student_thought_for_the_day', 'student_brain_spark'],
};
try {
  const hf = JSON.parse(fs.readFileSync(path.join(__dirname, 'hand_fixes.json'), 'utf8'));
  for (const [lang, vals] of Object.entries(hf)) {
    if (lang.startsWith('_') || lang === 'en') continue;
    HAND_SET[lang] = [...new Set([...(HAND_SET[lang] || []), ...Object.keys(vals)])];
  }
} catch (_) { /* no hand fixes file */ }

const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const REDO = new Set(((args.find(a => a.startsWith('--redo=')) || '').slice(7))
  .split(',').map(k => k.trim()).filter(Boolean));
const REDO_TERM = (args.find(a => a.startsWith('--redo-term=')) || '').slice(12).trim();
if (args.includes('--redo-overrides')) Object.keys(SOURCE_OVERRIDES).forEach(k => REDO.add(k));
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
  // --redo-term: keys whose English has the term; redone only in a pack
  // where the translation lost it (e.g. "AR" → "ए. आर.").
  const termKeys = new Set();
  if (REDO_TERM) {
    const re = new RegExp(`\\b${REDO_TERM}`);
    for (const k of Object.keys(en)) if (re.test(String(en[k]))) termKeys.add(k);
  }
  const keepEnglish = [];
  let total = 0;
  for (const lang of LANGS) {
    const pack = readPack(lang);
    const locked = new Set(HAND_SET[lang] || []);
    const todo = Object.keys(en).filter(k =>
      !locked.has(k) &&
      (!(k in pack) || REDO.has(k) ||
        (termKeys.has(k) && !String(pack[k]).includes(REDO_TERM))) &&
      /[A-Za-z]{2,}/.test(String(en[k])));
    const srcOf = k => String(SOURCE_OVERRIDES[k] ?? en[k]);
    total += todo.length;
    if (DRY || todo.length === 0) { console.log(`${lang}.json: ${todo.length} to translate`); continue; }
    let done = 0;
    for (let i = 0; i < todo.length; i += BATCH) {
      const keys = todo.slice(i, i + BATCH);
      const masked = keys.map(k => mask(srcOf(k)));
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
        // Rejected too if it mixes in another writing system (e.g. an Urdu
        // word in a Santali sentence).
        if (restored && restored !== en[k] && restored !== srcOf(k) && !foreignLetters(lang, restored)) {
          pack[k] = restored; done++;
        }
        else {
          // A redo that failed: drop the old (bad) text so English shows.
          // A --redo-term miss keeps the old text (e.g. "एक्सपी" is still readable).
          if (REDO.has(k)) delete pack[k];
          if (!(k in pack)) keepEnglish.push(`${lang}/${k}`);
        }
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
