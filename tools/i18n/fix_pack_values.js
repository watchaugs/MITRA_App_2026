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
// 5. Removes student_watched_pct_quiz_unlocked / _need_for_quiz and
//    student_highest_level_reached_gyani (replaced by shorter keys that
//    translate_missing.js fills in next).
'use strict';
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', '..', 'assets', 'locales');
const DRY = process.argv.includes('--dry-run');
const DROP = ['student_watched_pct_quiz_unlocked', 'student_watched_pct_need_for_quiz',
  'student_highest_level_reached_gyani'];

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
};
const TERMINATOR = /[\s]*[۔᱾꯫।॥.]+\s*$/u;
const TRAILING_DECOR = /[\p{Extended_Pictographic}\s→←\uFE0F\u200D]+$/u;

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

  for (const [k, byLang] of Object.entries(CONTEXT)) if (byLang[lang] && k in pack) set(k, byLang[lang]);

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
