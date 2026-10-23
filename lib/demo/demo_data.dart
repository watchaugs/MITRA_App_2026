// ═════════════════════════════════════════════════════════════
// DEMO DATA — offline seed for presentations  (v2)
//
// Powers THREE things with zero backend:
//   1. Home screen subject cards   (kDemoSubjects)
//   2. Learn tab quiz list         (kDemoQuizzes via DemoQuizRepository)
//   3. Quiz screen questions       (kDemoQuestions, 5+ each, detailed)
//
// To turn OFF after the demo: set kPresentationMode = false.
// ═════════════════════════════════════════════════════════════

import '../screens/student/learn_screen.dart';
import '../models/quiz_model.dart';

/// Master switch. true = offline demo data, false = live backend.
const bool kPresentationMode = true;

// ─────────────────────────────────────────────────────────────
// 1. HOME SCREEN SUBJECTS
// Plain maps so home_screen.dart can build its own Subject model
// from them (emoji / name / progress / ar count) without importing
// anything new. Colors are applied by the home screen itself.
// ─────────────────────────────────────────────────────────────
const List<Map<String, dynamic>> kDemoSubjects = [
  {'emoji': '🔬', 'name': 'Science', 'progress': 0.65, 'ar': 3},
  {'emoji': '📐', 'name': 'Maths', 'progress': 0.40, 'ar': 1},
  {'emoji': '🌍', 'name': 'Geography', 'progress': 0.80, 'ar': 2},
  {'emoji': '🏛️', 'name': 'History', 'progress': 0.25, 'ar': 1},
  {'emoji': '🔠', 'name': 'English', 'progress': 0.55, 'ar': 0},
];

// ─────────────────────────────────────────────────────────────
// 2. SEEDED QUIZZES  (grouped by subject via the `subject` field)
// ─────────────────────────────────────────────────────────────
const List<QuizSummary> kDemoQuizzes = [
  QuizSummary(
    id: 'sci-cell-basics',
    title: 'The Living Cell',
    subject: 'Science',
    topic: 'Biology · Cells',
    questionCount: 5,
    avgScore: 78,
    status: QuizStatus.live,
    languageTag: 'all',
  ),
  QuizSummary(
    id: 'sci-atom-basics',
    title: 'Inside the Atom',
    subject: 'Science',
    topic: 'Chemistry · Matter',
    questionCount: 5,
    avgScore: 71,
    status: QuizStatus.live,
    languageTag: 'all',
  ),
  QuizSummary(
    id: 'math-fractions',
    title: 'Fractions Warm-up',
    subject: 'Maths',
    topic: 'Numbers · Fractions',
    questionCount: 5,
    avgScore: 82,
    status: QuizStatus.live,
    languageTag: 'all',
  ),
  QuizSummary(
    id: 'geo-solar-system',
    title: 'Our Solar System',
    subject: 'Geography',
    topic: 'Space',
    questionCount: 5,
    avgScore: 88,
    status: QuizStatus.live,
    languageTag: 'all',
  ),
  QuizSummary(
    id: 'his-ancient-rome',
    title: 'Ancient Rome',
    subject: 'History',
    topic: 'World History',
    questionCount: 5,
    avgScore: 69,
    status: QuizStatus.live,
    languageTag: 'all',
  ),
  QuizSummary(
    id: 'eng-grammar-basics',
    title: 'Parts of Speech',
    subject: 'English',
    topic: 'Grammar',
    questionCount: 5,
    avgScore: 75,
    status: QuizStatus.live,
    languageTag: 'all',
  ),
];

// ─────────────────────────────────────────────────────────────
// 3. SEEDED QUESTIONS — 5+ per quiz, with detailed explanations
// ─────────────────────────────────────────────────────────────
const Map<String, List<QuizQuestion>> kDemoQuestions = {
  // ═══ SCIENCE · The Living Cell ═══
  'sci-cell-basics': [
    QuizQuestion(
      questionText: 'Which organelle is known as the "powerhouse" of the cell?',
      options: ['Nucleus', 'Mitochondria', 'Ribosome', 'Cell wall'],
      correctAnswerIndex: 1,
      explanation:
          'Mitochondria are called the powerhouse because they carry out cellular '
          'respiration — breaking down glucose to release energy stored as ATP, '
          'which powers almost every activity the cell performs.',
    ),
    QuizQuestion(
      questionText:
          'Which part of the cell controls what enters and leaves it?',
      options: ['Cytoplasm', 'Nucleus', 'Cell membrane', 'Vacuole'],
      correctAnswerIndex: 2,
      explanation:
          'The cell membrane is selectively permeable: it lets useful substances '
          'like oxygen and nutrients in, and pushes waste out, while blocking '
          'harmful material. This control keeps the cell\'s internal environment stable.',
    ),
    QuizQuestion(
      questionText: 'What gives plant cells their fixed, rigid shape?',
      options: ['Cell wall', 'Cell membrane', 'Chloroplast', 'Nucleus'],
      correctAnswerIndex: 0,
      explanation:
          'Plant cells have a tough outer cell wall made of cellulose surrounding '
          'the membrane. It provides structural support and protection, which is why '
          'plant cells keep a fixed rectangular shape while animal cells look rounder.',
    ),
    QuizQuestion(
      questionText: 'Where is most of the genetic material (DNA) stored?',
      options: ['Ribosome', 'Nucleus', 'Cytoplasm', 'Vacuole'],
      correctAnswerIndex: 1,
      explanation:
          'The nucleus is the control centre of the cell. It holds the DNA, which '
          'carries the instructions for building proteins and directing all cell '
          'activity — effectively the cell\'s "brain".',
    ),
    QuizQuestion(
      questionText:
          'Which structure carries out photosynthesis in plant cells?',
      options: ['Mitochondria', 'Chloroplast', 'Nucleus', 'Ribosome'],
      correctAnswerIndex: 1,
      explanation:
          'Chloroplasts contain the green pigment chlorophyll, which captures '
          'sunlight. They use that light energy to convert carbon dioxide and water '
          'into glucose and oxygen — the process we call photosynthesis.',
    ),
    QuizQuestion(
      questionText:
          'Which of these is found in an animal cell but NOT a plant cell?',
      options: ['Cell wall', 'Chloroplast', 'Centriole', 'Large vacuole'],
      correctAnswerIndex: 2,
      explanation:
          'Centrioles help organise cell division in animal cells. Cell walls, '
          'chloroplasts, and large permanent vacuoles are features of plant cells, '
          'so the centriole is the animal-only structure here.',
    ),
  ],

  // ═══ SCIENCE · Inside the Atom ═══
  'sci-atom-basics': [
    QuizQuestion(
      questionText: 'Which particle in an atom carries a negative charge?',
      options: ['Proton', 'Neutron', 'Electron', 'Nucleus'],
      correctAnswerIndex: 2,
      explanation:
          'Electrons carry a negative charge and orbit the nucleus in shells. '
          'Protons are positive, neutrons are neutral, so the electron is the only '
          'negatively charged particle in the atom.',
    ),
    QuizQuestion(
      questionText: 'What is the dense centre of an atom called?',
      options: ['Shell', 'Nucleus', 'Orbit', 'Ion'],
      correctAnswerIndex: 1,
      explanation:
          'The nucleus sits at the atom\'s centre and contains the protons and '
          'neutrons. It holds almost all of the atom\'s mass, even though it takes up '
          'a tiny fraction of the atom\'s total volume.',
    ),
    QuizQuestion(
      questionText: 'Which particle has a positive charge?',
      options: ['Electron', 'Neutron', 'Proton', 'Photon'],
      correctAnswerIndex: 2,
      explanation:
          'Protons carry a positive charge and are found in the nucleus. The number '
          'of protons (the atomic number) is what decides which element the atom is.',
    ),
    QuizQuestion(
      questionText: 'Which particle has no electrical charge at all?',
      options: ['Proton', 'Neutron', 'Electron', 'Ion'],
      correctAnswerIndex: 1,
      explanation:
          'Neutrons are electrically neutral — they have no charge. They sit in the '
          'nucleus alongside protons and add mass to the atom without affecting its '
          'overall charge.',
    ),
    QuizQuestion(
      questionText:
          'In a neutral atom, the number of protons equals the number of…',
      options: ['Neutrons', 'Electrons', 'Ions', 'Shells'],
      correctAnswerIndex: 1,
      explanation:
          'A neutral atom has no overall charge, so its positive protons must be '
          'balanced by an equal number of negative electrons. If this balance is '
          'broken, the atom becomes a charged ion.',
    ),
  ],

  // ═══ MATHS · Fractions ═══
  'math-fractions': [
    QuizQuestion(
      questionText: 'What is 1/2 + 1/4 ?',
      options: ['1/6', '2/6', '3/4', '1/3'],
      correctAnswerIndex: 2,
      explanation:
          'To add fractions you need a common denominator. 1/2 is the same as 2/4, '
          'so 2/4 + 1/4 = 3/4. Always convert to the same denominator before adding '
          'the top numbers.',
    ),
    QuizQuestion(
      questionText: 'Which of these fractions is the largest?',
      options: ['1/2', '1/3', '1/4', '1/5'],
      correctAnswerIndex: 0,
      explanation:
          'When the top number (numerator) is 1, the fraction with the smallest '
          'bottom number is largest, because the whole is split into fewer pieces. '
          'So 1/2 is bigger than 1/3, 1/4, or 1/5.',
    ),
    QuizQuestion(
      questionText: 'Simplify the fraction 4/8 to its lowest terms.',
      options: ['1/2', '2/3', '1/4', '3/4'],
      correctAnswerIndex: 0,
      explanation:
          'Divide the top and bottom by their largest common factor. Both 4 and 8 '
          'divide by 4: 4÷4 = 1 and 8÷4 = 2, giving 1/2. Simplifying makes fractions '
          'easier to compare and work with.',
    ),
    QuizQuestion(
      questionText: 'What is 3/5 written as a decimal?',
      options: ['0.35', '0.6', '0.53', '0.65'],
      correctAnswerIndex: 1,
      explanation:
          'A fraction is just a division: 3 ÷ 5 = 0.6. Dividing the numerator by the '
          'denominator always converts a fraction into its decimal form.',
    ),
    QuizQuestion(
      questionText: 'Which fraction is equal to 2/4 ?',
      options: ['1/2', '2/3', '3/4', '4/5'],
      correctAnswerIndex: 0,
      explanation:
          'Equivalent fractions have the same value even though they look different. '
          '2/4 simplifies to 1/2 (dividing both parts by 2), so 2/4 and 1/2 represent '
          'exactly the same amount.',
    ),
    QuizQuestion(
      questionText: 'What is 7/10 − 3/10 ?',
      options: ['4/10', '4/20', '10/10', '3/10'],
      correctAnswerIndex: 0,
      explanation:
          'When fractions already share the same denominator, just subtract the top '
          'numbers and keep the bottom the same: 7 − 3 = 4, giving 4/10 (which can '
          'also be simplified to 2/5).',
    ),
  ],

  // ═══ GEOGRAPHY · Solar System ═══
  'geo-solar-system': [
    QuizQuestion(
      questionText: 'Which is the largest planet in our solar system?',
      options: ['Earth', 'Saturn', 'Jupiter', 'Neptune'],
      correctAnswerIndex: 2,
      explanation:
          'Jupiter is by far the largest planet — so big that all the other planets '
          'could fit inside it. It is a gas giant made mostly of hydrogen and helium, '
          'with a famous Great Red Spot storm larger than Earth.',
    ),
    QuizQuestion(
      questionText: 'Which planet is known as the "Red Planet"?',
      options: ['Venus', 'Mars', 'Mercury', 'Jupiter'],
      correctAnswerIndex: 1,
      explanation:
          'Mars looks red because its surface is covered in iron oxide — the same '
          'compound as rust. That reddish dust gives it the nickname the Red Planet.',
    ),
    QuizQuestion(
      questionText: 'What sits at the centre of our solar system?',
      options: ['The Moon', 'Earth', 'The Sun', 'Jupiter'],
      correctAnswerIndex: 2,
      explanation:
          'The Sun, a star, sits at the centre. Its enormous gravity holds all the '
          'planets in orbit around it, and its light and heat make life on Earth '
          'possible.',
    ),
    QuizQuestion(
      questionText: 'Which planet is closest to the Sun?',
      options: ['Venus', 'Earth', 'Mercury', 'Mars'],
      correctAnswerIndex: 2,
      explanation:
          'Mercury is the closest planet to the Sun and also the smallest. Because '
          'it is so near, it races around the Sun in just 88 Earth days — the '
          'shortest year of any planet.',
    ),
    QuizQuestion(
      questionText: 'How many planets are there in our solar system?',
      options: ['7', '8', '9', '10'],
      correctAnswerIndex: 1,
      explanation:
          'There are 8 planets: Mercury, Venus, Earth, Mars, Jupiter, Saturn, '
          'Uranus, and Neptune. Pluto was reclassified as a "dwarf planet" in 2006, '
          'which is why the count is 8 and not 9.',
    ),
    QuizQuestion(
      questionText: 'Which planet is famous for its bright ring system?',
      options: ['Mars', 'Saturn', 'Venus', 'Mercury'],
      correctAnswerIndex: 1,
      explanation:
          'Saturn is best known for its stunning rings, made of countless pieces of '
          'ice and rock orbiting the planet. Other gas giants have faint rings too, '
          'but Saturn\'s are by far the brightest and most visible.',
    ),
  ],

  // ═══ HISTORY · Ancient Rome ═══
  'his-ancient-rome': [
    QuizQuestion(
      questionText: 'Ancient Rome was said to be built on how many hills?',
      options: ['Three', 'Five', 'Seven', 'Ten'],
      correctAnswerIndex: 2,
      explanation:
          'Rome is famously called the "City of Seven Hills". These hills along the '
          'River Tiber were where the earliest Roman settlements grew and later '
          'joined into one great city.',
    ),
    QuizQuestion(
      questionText:
          'What were the trained fighters who battled in Roman arenas called?',
      options: ['Knights', 'Gladiators', 'Samurai', 'Legionnaires'],
      correctAnswerIndex: 1,
      explanation:
          'Gladiators were fighters — often enslaved people or prisoners — who '
          'battled in arenas like the Colosseum for public entertainment. Some became '
          'famous and even won their freedom.',
    ),
    QuizQuestion(
      questionText: 'Which language did the ancient Romans speak?',
      options: ['Greek', 'Latin', 'Italian', 'Spanish'],
      correctAnswerIndex: 1,
      explanation:
          'The Romans spoke Latin. It went on to shape many modern languages — '
          'Italian, French, Spanish, Portuguese and Romanian all grew out of Latin, '
          'and English borrows thousands of Latin words too.',
    ),
    QuizQuestion(
      questionText:
          'What was the huge arena in Rome used for games and contests called?',
      options: ['The Pantheon', 'The Colosseum', 'The Forum', 'The Senate'],
      correctAnswerIndex: 1,
      explanation:
          'The Colosseum was a massive amphitheatre that could hold around 50,000 '
          'spectators. It hosted gladiator contests, mock battles and public '
          'spectacles, and much of it still stands in Rome today.',
    ),
    QuizQuestion(
      questionText: 'Who was the first Roman Emperor?',
      options: ['Julius Caesar', 'Augustus', 'Nero', 'Constantine'],
      correctAnswerIndex: 1,
      explanation:
          'Augustus became the first Roman Emperor in 27 BCE. Although Julius Caesar '
          'is more famous, he was a dictator, not an emperor — it was his adopted heir '
          'Augustus who founded the Roman Empire.',
    ),
  ],

  // ═══ ENGLISH · Parts of Speech ═══
  'eng-grammar-basics': [
    QuizQuestion(
      questionText:
          'In the sentence "The dog ran quickly", which word is a verb?',
      options: ['Dog', 'Ran', 'Quickly', 'The'],
      correctAnswerIndex: 1,
      explanation:
          'A verb is an action or "doing" word. "Ran" describes the action the dog '
          'is performing, so it is the verb. "Quickly" describes how it ran, which '
          'makes it an adverb.',
    ),
    QuizQuestion(
      questionText: 'Which word is a noun in "She read an interesting book"?',
      options: ['She', 'Read', 'Interesting', 'Book'],
      correctAnswerIndex: 3,
      explanation:
          'A noun names a person, place, thing or idea. "Book" is a thing, so it is '
          'the noun. "Interesting" describes the book (an adjective) and "read" is the '
          'action (a verb).',
    ),
    QuizQuestion(
      questionText: 'What part of speech is the word "happy"?',
      options: ['Noun', 'Verb', 'Adjective', 'Adverb'],
      correctAnswerIndex: 2,
      explanation:
          'An adjective describes a noun. "Happy" tells us more about a person or '
          'thing — a happy child, a happy day — so it is an adjective.',
    ),
    QuizQuestion(
      questionText: 'Which word is a pronoun in "They went to the market"?',
      options: ['They', 'Went', 'Market', 'To'],
      correctAnswerIndex: 0,
      explanation:
          'A pronoun replaces a noun so we don\'t have to repeat it. "They" stands in '
          'for a group of people instead of naming them again, which makes it a pronoun.',
    ),
    QuizQuestion(
      questionText: 'In "He sings beautifully", which word is an adverb?',
      options: ['He', 'Sings', 'Beautifully', 'None'],
      correctAnswerIndex: 2,
      explanation:
          'An adverb describes how, when or where an action happens, and many end in '
          '"-ly". "Beautifully" tells us how he sings, so it is the adverb modifying '
          'the verb "sings".',
    ),
  ],
};

// ─────────────────────────────────────────────────────────────
// DEMO REPOSITORY — drop-in replacement for ApiQuizRepository.
// ─────────────────────────────────────────────────────────────
class DemoQuizRepository implements QuizRepository {
  const DemoQuizRepository();

  @override
  Future<List<QuizSummary>> fetchLiveQuizzes(QuizFilterParams params) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return kDemoQuizzes;
  }
}
