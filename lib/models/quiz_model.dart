/// Question round types. A plain question is [mcq].
///   picture  → the options are pictures ([optionImages]) with optional
///              captions in [options]; [questionImage] is optional.
///   sequence → [options] are the steps in the RIGHT order; the quiz shuffles
///              them and the student puts them back in order.
enum QuizKind { mcq, picture, sequence }

class QuizQuestion {
  final String questionText;
  final List<String> options;
  final int correctAnswerIndex; // 0 for A, 1 for B, 2 for C, etc.
  final String? explanation; // Optional: Shows after they answer!
  final QuizKind kind;
  final String? questionImage; // picture round: picture shown with the question
  final List<String> optionImages; // picture round: one picture per option

  const QuizQuestion({
    required this.questionText,
    required this.options,
    required this.correctAnswerIndex,
    this.explanation,
    this.kind = QuizKind.mcq,
    this.questionImage,
    this.optionImages = const [],
  });

  bool get isPicture => kind == QuizKind.picture;
  bool get isSequence => kind == QuizKind.sequence;

  // ✨ BONUS: This will make fetching from Firebase incredibly easy later!
  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    return QuizQuestion(
      questionText: map['questionText'] ?? '',
      options: List<String>.from(map['options'] ?? []),
      correctAnswerIndex: map['correctAnswerIndex'] ?? 0,
      explanation: map['explanation'],
    );
  }

  /// Readable answer for the result screen. A sequence answer is the saved
  /// order code (see [encodeOrder]); a blank picture caption becomes
  /// "<pictureWord> A".
  String answerText(int index, {String pictureWord = 'Picture'}) {
    if (isSequence) {
      final order = decodeOrder(index, options.length);
      return [
        for (int i = 0; i < order.length; i++) '${i + 1}. ${options[order[i]]}'
      ].join('\n');
    }
    if (index < 0 || index >= options.length) return '';
    final t = options[index].trim();
    return t.isNotEmpty ? t : '$pictureWord ${String.fromCharCode(65 + index)}';
  }

  /// Round type + pictures, saved with a finished attempt for review.
  Map<String, dynamic> meta() => {
        'k': kind.name,
        if (questionImage != null) 'qi': questionImage,
        if (optionImages.isNotEmpty) 'oi': optionImages,
      };

  /// This question with the saved [meta] put back (null → unchanged).
  QuizQuestion withMeta(Object? m) {
    if (m is! Map) return this;
    final k = QuizKind.values
        .firstWhere((v) => v.name == m['k'], orElse: () => QuizKind.mcq);
    return QuizQuestion(
      questionText: questionText,
      options: options,
      correctAnswerIndex: correctAnswerIndex,
      explanation: explanation,
      kind: k,
      questionImage: m['qi'] is String ? m['qi'] as String : null,
      optionImages: m['oi'] is List
          ? (m['oi'] as List).map((e) => '$e').toList()
          : const [],
    );
  }
}

int _fact(int n) => n <= 1 ? 1 : n * _fact(n - 1);

/// A sequence answer is saved as ONE number so it fits the existing answer
/// lists: the Lehmer code of the order the student chose. `order[pos]` is the
/// index (in the right order) of the step placed at position `pos`, so the
/// right order encodes to 0. Up to 6 steps → 0..719.
int encodeOrder(List<int> order) {
  int code = 0;
  for (int i = 0; i < order.length; i++) {
    int smaller = 0;
    for (int j = i + 1; j < order.length; j++) {
      if (order[j] < order[i]) smaller++;
    }
    code += smaller * _fact(order.length - 1 - i);
  }
  return code;
}

/// Reverses [encodeOrder]. A bad code gives the right order.
List<int> decodeOrder(int code, int n) {
  if (n <= 0) return const [];
  if (code < 0 || code >= _fact(n)) code = 0;
  final left = List<int>.generate(n, (i) => i);
  final out = <int>[];
  for (int i = n - 1; i >= 0; i--) {
    final f = _fact(i);
    final d = code ~/ f;
    code %= f;
    out.add(left.removeAt(d));
  }
  return out;
}
