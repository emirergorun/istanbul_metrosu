import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/questions/question_repository.dart';

/// Yazılı soru havuzunun sağlığı.
///
/// Sorular elle yazılıyor; elle yazılan her şey bozulur. Bu testler
/// oyunun içinde fark edilmesi zor üç hatayı dosyada yakalar: eksik/çift
/// şık, yanlış cevap indeksi ve kaynaksız bilgi.
void main() {
  final dataset = QuestionDataset.parse(
    File('assets/data/questions.json').readAsStringSync(),
  );

  test('havuz boş değil', () {
    expect(dataset.questions().length, greaterThanOrEqualTo(40));
  });

  test('her sorunun 4 farklı şıkkı ve geçerli bir cevabı var', () {
    for (final question in dataset.questions()) {
      expect(question.options, hasLength(4), reason: question.id);
      expect(
        question.options.toSet(),
        hasLength(4),
        reason: 'şık tekrarı: ${question.id}',
      );
      expect(question.answerIndex, inInclusiveRange(0, 3), reason: question.id);
      expect(question.prompt.trim(), isNotEmpty, reason: question.id);
      for (final option in question.options) {
        expect(option.trim(), isNotEmpty, reason: question.id);
      }
    }
  });

  test('id tekrarı yok', () {
    final ids = dataset.questions().map((q) => q.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('her bilginin kaynağı yazılı', () {
    for (final question in dataset.questions()) {
      expect(
        question.source?.trim().isNotEmpty ?? false,
        isTrue,
        reason: 'kaynaksız soru: ${question.id}',
      );
    }
  });

  test('soru metni soru gibi bitiyor', () {
    for (final question in dataset.questions()) {
      expect(
        question.prompt.trim().endsWith('?'),
        isTrue,
        reason: 'soru işareti yok: ${question.id}',
      );
    }
  });
}
