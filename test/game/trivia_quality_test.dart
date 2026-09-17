import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/questions/question_repository.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/trivia_category.dart';

/// Veritabanının **oynanabilirlik** kalitesi.
///
/// Bütünlük testi (bkz. `trivia_database_test.dart`) dosyanın bozuk
/// olmadığını söyler; bu dosya oyunun tahmin edilebilir hâle gelip
/// gelmediğini ölçer. Sorular tek tek doğru olsa bile, doğru cevap hep
/// aynı yerdeyse ya da hep en uzun şıksa oyun bilgi değil örüntü sorar.
void main() {
  final dataset = QuestionDataset.parse(
    File('assets/data/trivia.json').readAsStringSync(),
  );
  final questions = dataset.questions();

  test('doğru cevap dört şıkka da dağılmış', () {
    final counts = <int, int>{0: 0, 1: 0, 2: 0, 3: 0};
    for (final q in questions) {
      counts[q.answerIndex] = counts[q.answerIndex]! + 1;
    }
    for (final entry in counts.entries) {
      final share = entry.value / questions.length;
      expect(
        share,
        inInclusiveRange(0.20, 0.30),
        reason: '${entry.key}. şıkkın payı: $share',
      );
    }
  });

  test('doğru cevabın yeri A-B-C-D diye sırayla ilerlemiyor', () {
    // Üretim aracının en kolay yaptığı hata: cevabı sırayla dağıtmak.
    // Oyuncu üç soruda örüntüyü fark eder ve okumayı bırakır.
    var cycles = 0;
    for (var i = 1; i < questions.length; i++) {
      final previous = questions[i - 1].answerIndex;
      if (questions[i].answerIndex == (previous + 1) % 4) cycles++;
    }
    final share = cycles / (questions.length - 1);
    expect(share, lessThan(0.40), reason: 'ardışık artan cevap oranı: $share');
  });

  test('doğru cevap sistematik olarak en uzun şık değil', () {
    var longest = 0;
    var shortest = 0;
    for (final q in questions) {
      final lengths = q.options.map((o) => o.length).toList();
      final max = lengths.reduce((a, b) => a > b ? a : b);
      final min = lengths.reduce((a, b) => a < b ? a : b);
      final answerLength = q.answer.length;
      // Beraberlik sayılmaz: yalnızca **tek başına** en uzun/en kısa olan.
      if (answerLength == max && lengths.where((l) => l == max).length == 1) {
        longest++;
      }
      if (answerLength == min && lengths.where((l) => l == min).length == 1) {
        shortest++;
      }
    }
    expect(
      longest / questions.length,
      lessThan(0.35),
      reason: 'doğru cevabın tek başına en uzun olduğu oran',
    );
    expect(
      shortest / questions.length,
      lessThan(0.35),
      reason: 'doğru cevabın tek başına en kısa olduğu oran',
    );
  });

  test('şıklar arasında "hepsi" / "hiçbiri" yok', () {
    const banned = <String>['hepsi', 'hiçbiri', 'yukarıdakilerin'];
    for (final q in questions) {
      for (final option in q.options) {
        final lower = option.toLowerCase();
        for (final word in banned) {
          expect(
            lower.contains(word),
            isFalse,
            reason: 'yasak şık "$option" (${q.id})',
          );
        }
      }
    }
  });

  test('her kategoride üç zorluk da var', () {
    for (final category in TriviaCategory.values) {
      final inCategory = dataset.byCategory(category);
      for (final difficulty in TriviaDifficulty.values) {
        final count = inCategory
            .where((q) => q.difficulty == difficulty)
            .length;
        expect(
          count,
          greaterThan(15),
          reason: '${category.id} / ${difficulty.id}: $count',
        );
      }
    }
  });

  test('kaynak adresleri tek bir siteye yığılmamış', () {
    final hosts = questions.map((q) => Uri.parse(q.source).host).toSet();
    expect(hosts.length, greaterThan(8), reason: 'kaynak çeşitliliği: $hosts');
  });
}
