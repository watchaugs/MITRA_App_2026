#!/usr/bin/env node
// One-off corrections to assets/locales/<lang>.json that machine translation
// got wrong. Safe to rerun: it only sets the values listed here.
//
//   node tools/i18n/fix_pack_values.js            # apply
//   node tools/i18n/fix_pack_values.js --dry-run  # show what would change
//
// 1. Tier names (tier_*): Bhashini spelled the Sanskrit words phonetically
//    (जिग्यासु, विदवान, ग्यानी). These are the proper spellings per script.
// 2. student_viewed: the "✓" was read as the letter "Y" ("वाय व्यूव्ड").
//    The tick now lives in the code; packs carry only the word.
// 3. Stray "Â" characters (a broken emoji/encoding left by MT) are removed and
//    the English value's leading/trailing emoji is put back.
// 4. auth_namaste (greeting screen) and student_notice: MT produced
//    things like "ਐੱਨ. ਏ. ਐੱਮ. ਐੱਸ. ਟੀ. ਈ" or "notice karein"; set by hand.
// 6. Context fixes: short labels translated without knowing where they sit
//    ("Support" in Settings came out as political "support", "About" as a bare
//    preposition, Tamil "Finish" as "hair"). Set by hand per language below.
// 7. Labels that have no full stop in English lose the sentence terminator MT
//    added (۔ ᱾ ꯫ । .) — Kashmiri and Santali ended almost every button with one.
// 9. Every Indic script (not Sanskrit, not Tamil): the same colon-as-visarga
//    fix for Bengali/Assamese ঃ, Gujarati ઃ, Kannada ಃ, Malayalam ഃ, Telugu ః,
//    Punjabi ਃ and Odia ଃ.
// 10. The emoji at the start ("💭 Thought for the day", "🔥 …") and the arrow
//    at the end ("Send OTP →") are put back when MT dropped them.
// 11. Letters from another writing system inside a pack (an Urdu word in a
//    Santali sentence, a Hindi word in Manipuri): known words are replaced,
//    anything else is removed so English shows until it is translated again.
// 12. Small MT glitches: an arrow moved into the middle, a lost trailing "…",
//    "XP·" without spaces, a space before an apostrophe (ল 'ড), stray ′ marks,
//    Santali ᱾ used as a colon, and a lost "XXXXXXX" mask (value dropped).
// 8. Devanagari packs (not Sanskrit): MT wrote the colon as a visarga ("सकाः {v1}"). Where the
//    English has a colon, "ः" before a space/placeholder becomes ": " — real
//    visarga words (पुनः, अतः, प्रातः …) are left alone.
// 5. Removes student_watched_pct_quiz_unlocked / _need_for_quiz and
//    student_highest_level_reached_gyani (replaced by shorter keys that
//    translate_missing.js fills in next).
'use strict';
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', '..', 'assets', 'locales');
const DRY = process.argv.includes('--dry-run');
const DROP = ['student_watched_pct_quiz_unlocked', 'student_watched_pct_need_for_quiz',
  'student_highest_level_reached_gyani',
  // "100%" was hard-coded; replaced by *_pct keys that take the dashboard's mastery %.
  'quiz_100_mastery_achieved', 'quiz_you_must_score_100_to_unlock', 'student_score_100_on_the_previous_module',
  'student_completed_100', 'student_locked_title_score_100_on_the'];

const DEVA = ['जिज्ञासु', 'अन्वेषक', 'विद्वान', 'आचार्य', 'ज्ञानी'];
const URDU = ['جگیاسو', 'انویشک', 'ودوان', 'آچاریہ', 'گیانی'];

// [jigyasu, anveshak, vidwan, acharya, gyani], viewed (null = keep current)
const FIX = {
  hi:  [DEVA, 'देखा गया'],
  mai: [DEVA, 'देखल गेल'],
  ne:  [DEVA, 'हेरियो'],
  doi: [DEVA, 'दिक्खेआ'],
  brx: [DEVA, null],
  mr:  [['जिज्ञासू', 'अन्वेषक', 'विद्वान', 'आचार्य', 'ज्ञानी'], 'पाहिले'],
  sa:  [['जिज्ञासुः', 'अन्वेषकः', 'विद्वान्', 'आचार्यः', 'ज्ञानी'], 'दृष्टम्'],
  gu:  [['જિજ્ઞાસુ', 'અન્વેષક', 'વિદ્વાન', 'આચાર્ય', 'જ્ઞાની'], 'જોયું'],
  bn:  [['জিজ্ঞাসু', 'অন্বেষক', 'বিদ্বান', 'আচার্য', 'জ্ঞানী'], 'দেখা হয়েছে'],
  as:  [['জিজ্ঞাসু', 'অন্বেষক', 'বিদ্বান', 'আচাৰ্য', 'জ্ঞানী'], 'চোৱা হৈছে'],
  or:  [['ଜିଜ୍ଞାସୁ', 'ଅନ୍ୱେଷକ', 'ବିଦ୍ୱାନ', 'ଆଚାର୍ଯ୍ୟ', 'ଜ୍ଞାନୀ'], 'ଦେଖାଗଲା'],
  pa:  [['ਜਿਗਿਆਸੂ', 'ਅਨਵੇਸ਼ਕ', 'ਵਿਦਵਾਨ', 'ਆਚਾਰੀਆ', 'ਗਿਆਨੀ'], 'ਦੇਖਿਆ ਗਿਆ'],
  kn:  [['ಜಿಜ್ಞಾಸು', 'ಅನ್ವೇಷಕ', 'ವಿದ್ವಾನ್', 'ಆಚಾರ್ಯ', 'ಜ್ಞಾನಿ'], 'ವೀಕ್ಷಿಸಲಾಗಿದೆ'],
  te:  [['జిజ్ఞాసు', 'అన్వేషక్', 'విద్వాన్', 'ఆచార్య', 'జ్ఞాని'], 'వీక్షించబడింది'],
  ta:  [['ஜிக்ஞாசு', 'அன்வேஷக்', 'வித்வான்', 'ஆச்சார்யா', 'ஞானி'], 'பார்க்கப்பட்டது'],
  ml:  [['ജിജ്ഞാസു', 'അന്വേഷക്', 'വിദ്വാൻ', 'ആചാര്യ', 'ജ്ഞാനി'], 'കണ്ടു'],
  ur:  [URDU, 'دیکھا گیا'],
  ks:  [URDU, 'ۄچھینہٕ آمت'],
  sd:  [['جگياسو', 'انويشڪ', 'ودوان', 'آچاريه', 'گياني'], 'ڏٺو ويو'],
  sat: [['ᱡᱤᱜᱤᱭᱟᱥᱩ', 'ᱚᱱᱵᱷᱮᱥᱚᱠ', 'ᱵᱤᱫᱳᱣᱟᱱ', 'ᱟᱪᱟᱨᱡᱚ', 'ᱜᱤᱭᱟᱱᱤ'], 'ᱧᱮᱞ ᱟᱠᱟᱱᱟ'],
  mni: [['ꯖꯤꯒ꯭ꯌꯥꯁꯨ', 'ꯑꯟꯚꯦꯁꯥꯛ', 'ꯕꯤꯗꯋꯥꯟ', 'ꯑꯥꯆꯥꯔꯌ', 'ꯒ꯭ꯌꯥꯅꯤ'], 'ꯌꯦꯡꯂꯦ'],
};
// Greeting and notice label, by hand. 🙏🏽 / 📢 are added below.
const NAMASTE = {
  as: 'নমস্কাৰ', bn: 'নমস্কার', brx: 'खुलुमबाय', doi: 'नमस्ते', gu: 'નમસ્તે',
  hi: 'नमस्ते', kn: 'ನಮಸ್ಕಾರ', ks: 'نمستے', mai: 'प्रणाम', ml: 'നമസ്കാരം',
  mni: 'ꯈꯨꯔꯨꯝꯖꯔꯤ', mr: 'नमस्कार', ne: 'नमस्ते', or: 'ନମସ୍କାର', pa: 'ਨਮਸਤੇ',
  sa: 'नमस्ते', sat: 'ᱡᱚᱦᱟᱨ', sd: 'نمستي', ta: 'வணக்கம்', te: 'నమస్కారం', ur: 'نمستے',
};
const NOTICE = {
  brx: 'नोटिस', gu: 'નોટિસ', mai: 'सूचना', sat: 'ᱱᱳᱴᱤᱥ', sd: 'اطلاع',
  ta: 'அறிவிப்பு', te: 'నోటీసు', ur: 'نوٹس',
};
// Context fixes: key -> { lang: value }. Only languages checked by hand.
const CONTEXT = {
  student_support: { hi: 'सहायता', mr: 'मदत', ne: 'सहायता', mai: 'सहायता', doi: 'मदद', sa: 'सहायता',
    gu: 'મદદ', bn: 'সহায়তা', as: 'সহায়', or: 'ସହାୟତା', pa: 'ਸਹਾਇਤਾ', kn: 'ಸಹಾಯ', te: 'సహాయం',
    ta: 'உதவி', ml: 'സഹായം', ur: 'مدد', ks: 'مدد', sd: 'مدد' },
  student_about: { hi: 'ऐप के बारे में', mr: 'ॲपविषयी', ne: 'एपको बारेमा', mai: 'ऐपक बारेमे', doi: 'ऐप बारे',
    sa: 'परिचयः', gu: 'એપ વિશે', bn: 'অ্যাপ সম্পর্কে', as: 'এপৰ বিষয়ে', or: 'ଆପ୍ ବିଷୟରେ', pa: 'ਐਪ ਬਾਰੇ',
    kn: 'ಆ್ಯಪ್ ಬಗ್ಗೆ', te: 'యాప్ గురించి', ta: 'செயலி பற்றி', ml: 'ആപ്പിനെക്കുറിച്ച്', ur: 'ایپ کے بارے میں',
    sd: 'ايپ بابت' },
  ar_got_it: { gu: 'સમજાઈ ગયું', bn: 'বুঝেছি', as: 'বুজি পালোঁ', kn: 'ಅರ್ಥವಾಯಿತು', ne: 'बुझेँ', or: 'ବୁଝିଗଲି',
    sa: 'अवगतम्', sd: 'سمجهي ويو', mr: 'समजले', mai: 'बुझलहुँ' },
  quiz_finish: { ta: 'முடிக்கவும்', sd: 'ختم ڪريو' },
  btn_retry: { ta: 'மீண்டும் முயல்க', ml: 'വീണ്ടും ശ്രമിക്കുക', ur: 'دوبارہ کوشش کریں' },
  btn_back: { hi: '← वापस', ta: '← பின் செல்' },
  home_topics: { hi: 'टॉपिक', gu: 'ટોપિક', mai: 'टॉपिक', ne: 'टपिक', doi: 'टॉपिक', as: 'টপিক', or: 'ଟପିକ୍' },
  student_subject: { ta: 'பாடம்', ne: 'विषय' },
  txt_all: { mr: 'सर्व', as: 'সকলো', bn: 'সব' },
  // MT returned "Step 2 – start the programme".
  auth_step_4_of_4: { ks: 'مرحلہ 4 / 4' },
  // School class: MT used वर्ग / ವರ್ಗ ("category"). Gujarati uses ધોરણ for a grade.
  auth_class_number: { ne: 'कक्षा {number}', mai: 'कक्षा {number}', doi: 'कक्षा {number}', kn: 'ತರಗತಿ {number}', gu: 'ધોરણ {number}' },
  student_select_class: { doi: 'कक्षा चुनो', kn: 'ತರಗತಿಯನ್ನು ಆಯ್ಕೆ ಮಾಡಿ', gu: 'ધોરણ પસંદ કરો' },
  teacher_class_average: { doi: 'कक्षा औसत', kn: 'ತರಗತಿಯ ಸರಾಸರಿ' },
  settings_change_class: { kn: 'ತರಗತಿಯನ್ನು ಬದಲಾಯಿಸಿ', gu: 'ધોરણ બદલો' },
  settings_tap_to_select_a_new_class: { kn: 'ಹೊಸ ತರಗತಿಯನ್ನು ಆಯ್ಕೆ ಮಾಡಲು ಟ್ಯಾಪ್ ಮಾಡಿ', gu: 'નવું ધોરણ પસંદ કરવા માટે ટેપ કરો' },
  // MT pushed MITRA to the end of the sentence.
  auth_update_mitra_to_continue: {
    gu: 'ચાલુ રાખવા માટે MITRA અપડેટ કરો', ne: 'जारी राख्न MITRA अद्यावधिक गर्नुहोस्',
    mai: 'जारी रखबाक लेल MITRA अद्यतन करू', doi: 'जारी रखने आस्तै MITRA अपडेट करो',
    ml: 'തുടരാൻ MITRA അപ്ഡേറ്റ് ചെയ്യുക', pa: 'ਜਾਰੀ ਰੱਖਣ ਲਈ MITRA ਅੱਪਡੇਟ ਕਰੋ',
    ta: 'தொடர MITRA-வைப் புதுப்பிக்கவும்', te: 'కొనసాగడానికి MITRAను నవీకరించండి',
  },
};
const TERMINATOR = /[\s]*[۔᱾꯫।॥.]+\s*$/u;
const TRAILING_DECOR = /[\p{Extended_Pictographic}\s→←\uFE0F\u200D]+$/u;

// Sanskrit left out: there a word-final visarga is usually real grammar.
// The visarga sign of each script; Sanskrit and Tamil are left out (a final
// visarga / aytham there is usually real grammar).
const VISARGA_OF = {
  hi: 'ः', mr: 'ः', ne: 'ः', mai: 'ः', doi: 'ः', brx: 'ः',
  as: 'ঃ', bn: 'ঃ', gu: 'ઃ', kn: 'ಃ', ml: 'ഃ', te: 'ః', pa: 'ਃ', or: 'ଃ',
};
// Words that really end in a visarga — never turned into a colon.
const VISARGA_WORDS = new Set(['पुनः', 'अतः', 'प्रातः', 'स्वतः', 'प्रायः', 'क्रमशः', 'अंततः',
  'संभवतः', 'सम्भवतः', 'सामान्यतः', 'मुख्यतः', 'वस्तुतः', 'पूर्णतः', 'विशेषतः', 'नमः', 'अधः', 'मनः', 'ततः', 'यतः',
  'পুনঃ', 'অতঃ', 'প্রাতঃ', 'স্বতঃ', 'পুনঃপুনঃ', 'પુનઃ', 'અતઃ', 'સ્વતઃ', 'ಪುನಃ', 'ಅತಃ', 'ಸ್ವತಃ',
  'പുനഃ', 'పునః', 'అతః', 'స్వతః', 'ପୁନଃ', 'ଅତଃ']);
function fixVisargaColon(src, val, mark = 'ः') {
  const want = (src.match(/:/g) || []).length;
  if (!want || !val.includes(mark)) return val;
  let done = 0;
  const re = new RegExp(`(\\S*?)${mark}(?=\\s|\\{|$)`, 'gu');
  return val.replace(re, (m, word) => {
    if (done >= want || VISARGA_WORDS.has(word + mark)) return m;
    done++;
    return word + ':';
  });
}

const { foreignLetters } = require('./script_check');
// Known words MT wrote in the wrong script → the pack's own spelling.
const SCRIPT_FIX = {
  sat: [['ماڈل', 'ᱢᱚᱰᱮᱞ']],   // "model" (spelled ᱢᱚᱰᱮᱞ elsewhere in sat.json)
  mni: [['पाउखुम', 'ꯄꯥꯎꯈꯨꯝ']],  // "answer"
};
const RTL = new Set(['ur', 'ks', 'sd']);
const LEAD_DECOR = /^[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\uFE0F\u200D]+/u;

const TIER_KEYS = ['tier_jigyasu', 'tier_anveshak', 'tier_vidwan', 'tier_acharya', 'tier_gyani'];

const en = JSON.parse(fs.readFileSync(path.join(DIR, 'en.json'), 'utf8'));
const EMOJI = /^[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\uFE0F\u200D]+/u;
const EMOJI_END = /[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\uFE0F\u200D]+$/u;

let total = 0;
for (const [lang, [tiers, viewed]] of Object.entries(FIX)) {
  const file = path.join(DIR, `${lang}.json`);
  const pack = JSON.parse(fs.readFileSync(file, 'utf8'));
  const changes = [];
  const set = (k, v) => { if (pack[k] !== v) { changes.push(`${k}: ${JSON.stringify(pack[k])} -> ${JSON.stringify(v)}`); pack[k] = v; } };

  TIER_KEYS.forEach((k, i) => set(k, tiers[i]));
  if (viewed !== null) set('student_viewed', viewed);
  else if (typeof pack.student_viewed === 'string') set('student_viewed', pack.student_viewed.replace(/[✓\s]+/g, ' ').trim());

  if (NAMASTE[lang]) set('auth_namaste', `${NAMASTE[lang]} 🙏🏽`);
  if (NOTICE[lang]) set('student_notice', `📢 ${NOTICE[lang]}`);

  for (const k of Object.keys(pack)) {
    if (typeof pack[k] !== 'string' || !pack[k].includes('Â')) continue;
    let v = pack[k].replace(/Â/g, ' ').replace(/[\s۔]+$/u, '').replace(/\s+/g, ' ').trim();
    const src = String(en[k] || '');
    const lead = (src.match(EMOJI) || [''])[0];
    const trail = (src.match(EMOJI_END) || [''])[0];
    if (lead && !v.startsWith(lead)) v = `${lead} ${v}`;
    if (trail && !v.endsWith(trail)) v = `${v} ${trail}`;
    set(k, v);
  }

  for (const [k, byLang] of Object.entries(CONTEXT)) if (byLang[lang] && (k in pack || k in en)) set(k, byLang[lang]);

  if (VISARGA_OF[lang]) {
    for (const k of Object.keys(pack)) {
      if (typeof pack[k] !== 'string' || typeof en[k] !== 'string') continue;
      const v = fixVisargaColon(en[k], pack[k], VISARGA_OF[lang]);
      if (v !== pack[k]) set(k, v);
    }
  }

  // Put back the leading emoji and the trailing arrow MT dropped.
  for (const k of Object.keys(pack)) {
    if (typeof pack[k] !== 'string' || typeof en[k] !== 'string' || !pack[k].trim()) continue;
    let v = pack[k];
    const lead = (en[k].match(LEAD_DECOR) || [''])[0];
    if (lead && !v.startsWith(lead)) v = `${lead} ${v.replace(LEAD_DECOR, '').trim()}`;
    // An arrow MT moved into the middle ("OTP → పంపండి") is taken out first.
    if (/→\s*$/.test(en[k]) && (en[k].match(/→/g) || []).length === 1) {
      v = v.replace(/\s*→\s*(?=\S)/g, ' ').trim();
    }
    // Arrows only for left-to-right scripts (in Urdu/Kashmiri/Sindhi they would point backwards).
    if (!RTL.has(lang) && /→\s*$/.test(en[k]) && !/→\s*$/.test(v)) v = `${v.trim()} →`;
    if (!RTL.has(lang) && /^\s*←/.test(en[k]) && !/^\s*←/.test(v)) v = `← ${v.trim()}`;
    // Trailing "…" of a status line ("Getting your missions ready…").
    if (/(…|\.\.\.)\s*$/.test(en[k]) && !/(…|\.\.\.)\s*$/.test(v)) v = `${v.replace(TERMINATOR, '').trim()}…`;
    // "XP· 20" → "XP · 20" when English has a spaced middle dot.
    if (en[k].includes(' · ')) v = v.replace(/\s*·\s*/g, ' · ');
    // A space MT put before an apostrophe inside a word ("ल 'ड" → "ल'ड").
    if (!en[k].includes("'")) v = v.replace(/([\p{L}\p{M}]) '(?=[\p{L}\p{M}])/gu, "$1'");
    // Stray prime marks (′ ″) MT left where an emoji or quote was.
    if (!/[′″]/.test(en[k])) v = v.replace(/\s*[′″]+\s*/g, ' ').trim();
    // Santali: MT wrote the full stop ᱾ where English has a colon before a value.
    if (lang === 'sat' && en[k].includes(':') && !v.includes(':')) v = v.replace(/\s*᱾\s*(?=\{)/u, ': ');
    if (v !== pack[k]) set(k, v);
  }

  // A literal mask such as "XXXXXXX" lost by MT: drop the value so English shows.
  for (const k of Object.keys(pack)) {
    const keep = String(en[k] || '').match(/X{4,}/g);
    if (typeof pack[k] !== 'string' || !keep || keep.every(t => pack[k].includes(t))) continue;
    changes.push(`${k}: removed (lost ${keep.join(' ')}) — English shows`);
    delete pack[k];
  }

  // Wrong writing system inside the pack.
  for (const [bad, good] of SCRIPT_FIX[lang] || []) {
    for (const k of Object.keys(pack)) {
      if (typeof pack[k] === 'string' && pack[k].includes(bad)) set(k, pack[k].split(bad).join(good));
    }
  }
  for (const k of Object.keys(pack)) {
    if (typeof pack[k] !== 'string' || !foreignLetters(lang, pack[k])) continue;
    changes.push(`${k}: removed (letters from another script: ${foreignLetters(lang, pack[k])}) — English shows`);
    delete pack[k];
  }

  // Strip a sentence terminator MT added to a label that has none in English.
  for (const k of Object.keys(pack)) {
    const src = String(en[k] || '').replace(TRAILING_DECOR, '');
    if (typeof pack[k] !== 'string' || !src || /[.!?।:…]$/.test(src)) continue;
    if (TERMINATOR.test(pack[k])) set(k, pack[k].replace(TERMINATOR, ''));
  }

  for (const k of DROP) if (k in pack) { changes.push(`${k}: removed`); delete pack[k]; }

  if (changes.length) {
    console.log(`${lang}.json (${changes.length})`);
    changes.forEach(c => console.log('   ' + c));
    total += changes.length;
    if (!DRY) fs.writeFileSync(file, JSON.stringify(pack, null, 2) + '\n', 'utf8');
  }
}
console.log(`${DRY ? 'would change' : 'changed'} ${total} value(s)`);
