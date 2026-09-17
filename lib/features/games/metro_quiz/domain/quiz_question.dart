import 'package:flutter/foundation.dart';

import '../../../../data/questions/question_repository.dart';
import 'trivia_category.dart';

/// Dört şıklı tek soru — ekranın gördüğü biçim.
///
/// Veri katmanındaki [TriviaQuestion] ile neredeyse aynı; ayrı durmasının
/// sebebi sunum katmanının veri dosyasının biçimine bağlanmaması. Depo
/// yarın başka bir kaynağa taşınırsa ekran değişmez.
@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.prompt,
    required this.options,
    required this.answerIndex,
    this.explanation,
  });

  factory QuizQuestion.fromTrivia(TriviaQuestion q) => QuizQuestion(
    id: q.id,
    category: q.category,
    difficulty: q.difficulty,
    prompt: q.prompt,
    options: q.options,
    answerIndex: q.answerIndex,
    explanation: q.explanation,
  );

  /// Aynı soruyu bir yolculukta iki kez sormamak için kullanılır.
  final String id;

  /// Sorunun kategorisi; ekranda sorunun **üstünde** gösterilir.
  final TriviaCategory category;

  final TriviaDifficulty difficulty;
  final String prompt;
  final List<String> options;
  final int answerIndex;

  /// Cevap gösterilirken çıkan tek cümlelik not; çoğu soruda boş.
  final String? explanation;

  String get answer => options[answerIndex];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is QuizQuestion && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'QuizQuestion($id, ${category.id})';
}
