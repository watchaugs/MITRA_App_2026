// MITRA — the ONE list of Indian states and union territories (app copy).
//
// Must stay identical to the Dashboard file public/mitra-states.js (same
// codes, names, aliases, order). After changing either, run from the
// Dashboard repo:  node scripts/check_states_sync.js <path-to-app-repo>
//
// code    — the state's MITRA code; matches the Curriculum Map (e.g. "GJ").
// name    — the official English name; what profiles store and screens show.
// aliases — other spellings / older codes from data, maps and GPS lookups
//           (Orissa/OR, DN/DH, UT, TS, CG …). They all mean the same state.

class IndiaState {
  final String code;
  final String name;
  final List<String> aliases;
  const IndiaState(this.code, this.name, [this.aliases = const []]);
}

const List<IndiaState> kIndiaStates = [
  IndiaState('AN', 'Andaman and Nicobar Islands', ['Andaman and Nicobar', 'Andaman & Nicobar Islands', 'A&N Islands']),
  IndiaState('AP', 'Andhra Pradesh'),
  IndiaState('AR', 'Arunachal Pradesh'),
  IndiaState('AS', 'Assam'),
  IndiaState('BR', 'Bihar'),
  IndiaState('CH', 'Chandigarh'),
  IndiaState('CT', 'Chhattisgarh', ['CG', 'Chattisgarh']),
  IndiaState('DD', 'Dadra and Nagar Haveli and Daman and Diu', ['DN', 'DH', 'Dadra and Nagar Haveli', 'Daman and Diu', 'Dadra & Nagar Haveli and Daman & Diu']),
  IndiaState('DL', 'Delhi', ['NCT of Delhi', 'National Capital Territory of Delhi', 'New Delhi']),
  IndiaState('GA', 'Goa'),
  IndiaState('GJ', 'Gujarat'),
  IndiaState('HR', 'Haryana'),
  IndiaState('HP', 'Himachal Pradesh'),
  IndiaState('JK', 'Jammu and Kashmir', ['Jammu & Kashmir', 'Jammu and Kashmir Union Territory']),
  IndiaState('JH', 'Jharkhand'),
  IndiaState('KA', 'Karnataka'),
  IndiaState('KL', 'Kerala'),
  IndiaState('LA', 'Ladakh'),
  IndiaState('LD', 'Lakshadweep'),
  IndiaState('MP', 'Madhya Pradesh'),
  IndiaState('MH', 'Maharashtra'),
  IndiaState('MN', 'Manipur'),
  IndiaState('ML', 'Meghalaya'),
  IndiaState('MZ', 'Mizoram'),
  IndiaState('NL', 'Nagaland'),
  IndiaState('OD', 'Odisha', ['OR', 'Orissa']),
  IndiaState('PY', 'Puducherry', ['Pondicherry']),
  IndiaState('PB', 'Punjab'),
  IndiaState('RJ', 'Rajasthan'),
  IndiaState('SK', 'Sikkim'),
  IndiaState('TN', 'Tamil Nadu'),
  IndiaState('TG', 'Telangana', ['TS']),
  IndiaState('TR', 'Tripura'),
  IndiaState('UP', 'Uttar Pradesh'),
  IndiaState('UK', 'Uttarakhand', ['UT', 'Uttaranchal']),
  IndiaState('WB', 'West Bengal'),
];

String _norm(String v) => v
    .trim()
    .toLowerCase()
    .replaceAll("&", "and")
    .replaceAll(RegExp(r"[^a-z0-9]"), "");

final Map<String, IndiaState> _byKey = {
  for (final s in kIndiaStates)
    for (final f in [s.code, s.name, ...s.aliases]) _norm(f): s,
};

/// The state for any form ("Gujarat", "GJ", "gujarat", "Orissa"), or null.
IndiaState? findIndiaState(String? value) {
  if (value == null) return null;
  final k = _norm(value);
  return k.isEmpty ? null : _byKey[k];
}

/// MITRA code ("GJ") for any form, or null if unknown.
String? indiaStateCode(String? value) => findIndiaState(value)?.code;

/// Official name ("Gujarat") for any form, or null if unknown.
String? indiaStateName(String? value) => findIndiaState(value)?.name;

/// Same state? Works across codes, names, case and old spellings.
bool sameIndiaState(String? a, String? b) {
  final sa = findIndiaState(a), sb = findIndiaState(b);
  if (sa != null && sb != null) return sa.code == sb.code;
  final na = _norm(a ?? "");
  return na.isNotEmpty && na == _norm(b ?? "");
}
