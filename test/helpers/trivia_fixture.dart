import 'dart:io';

import 'package:istanbul_metro_game/data/questions/question_repository.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/trivia_category.dart';

/// Testler için soru havuzu.
///
/// Gerçek `assets/data/trivia.json` dosyasından okur: oyun kurallarını
/// uydurma veriyle sınamak, veri ile kuralın birlikte çalıştığını
/// göstermez. Küçük havuz gerektiğinde [repository] kategori başına kaç
/// soru alınacağını sınırlar.
class TriviaFixture {
  const TriviaFixture._();

  static QuestionDataset? _cached;

  static QuestionDataset full() {
    return _cached ??= QuestionDataset.parse(
      File('assets/data/trivia.json').readAsStringSync(),
    );
  }

  /// Kategori başına en fazla [perCategory] soru içeren havuz.
  ///
  /// Zorluk dağılımı korunur: her zorluktan sırayla alınır, yoksa oyunun
  /// "önce kolay" kuralı test havuzunda hiç çalışmazdı.
  static QuestionRepository repository({int? perCategory}) {
    final all = full();
    if (perCategory == null) return all;

    final picked = <TriviaQuestion>[];
    for (final category in TriviaCategory.values) {
      final inCategory = all.byCategory(category);
      for (final difficulty in TriviaDifficulty.values) {
        picked.addAll(
          inCategory.where((q) => q.difficulty == difficulty).take(perCategory),
        );
      }
    }
    return _FixedRepository(picked);
  }
}

class _FixedRepository implements QuestionRepository {
  _FixedRepository(this._questions);

  final List<TriviaQuestion> _questions;

  @override
  List<TriviaQuestion> questions() => _questions;

  @override
  List<TriviaQuestion> byCategory(TriviaCategory category) =>
      _questions.where((q) => q.category == category).toList();
}
