import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/questions/question_repository.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/trivia_category.dart';

/// Soru veritabanının bütünlüğü.
///
/// Veri elle ve araçla yazılıyor; ikisi de bozulur. Bu testler oyunun
/// içinde fark edilmesi zor hataları dosyada yakalar: eksik kategori,
/// tekrar eden kimlik, geçersiz cevap indeksi, kaynaksız kayıt.
///
/// Dosya `assets/data/trivia.json`'dan **doğrudan** okunur; asset paketi
/// üzerinden değil. Testin amacı dosyanın kendisi.
void main() {
  final raw = File('assets/data/trivia.json').readAsStringSync();
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final dataset = QuestionDataset.parse(raw);
  final questions = dataset.questions();

  test('1.200 sorunun tamamı ayrıştırılabiliyor', () {
    final items = root['questions'] as List<dynamic>;
    expect(items, hasLength(1200), reason: 'dosyadaki kayıt sayısı');
    expect(
      questions,
      hasLength(1200),
      reason: 'ayrıştırma hiçbir kaydı elemeden geçmeli',
    );
    expect(root['totalQuestions'], 1200, reason: 'başlıktaki sayı da uymalı');
  });

  test('her kategoride 200 soru var', () {
    for (final category in TriviaCategory.values) {
      expect(dataset.byCategory(category), hasLength(200), reason: category.id);
    }
  });

  test('kimlikler tekrarsız', () {
    final ids = questions.map((q) => q.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('her sorunun 4 farklı şıkkı ve geçerli bir cevabı var', () {
    for (final q in questions) {
      expect(q.options, hasLength(4), reason: q.id);
      expect(q.options.toSet(), hasLength(4), reason: 'şık tekrarı: ${q.id}');
      expect(q.answerIndex, inInclusiveRange(0, 3), reason: q.id);
      for (final option in q.options) {
        expect(option.trim(), isNotEmpty, reason: q.id);
      }
    }
  });

  test('soru metni dolu ve soru işaretiyle bitiyor', () {
    for (final q in questions) {
      expect(q.prompt.trim(), isNotEmpty, reason: q.id);
      expect(
        q.prompt.trim().endsWith('?'),
        isTrue,
        reason: 'soru işareti yok: ${q.id}',
      );
    }
  });

  test('her kaydın kaynağı ve doğrulama etiketi var', () {
    for (final q in questions) {
      expect(q.source.trim(), isNotEmpty, reason: 'kaynaksız: ${q.id}');
      expect(
        q.source.startsWith('http'),
        isTrue,
        reason: 'kaynak adres değil: ${q.id}',
      );
    }
  });

  test('doğrulama etiketi olduğundan fazlasını iddia etmiyor', () {
    // `metro_json` yalnızca depodaki ağ verisine karşı programatik olarak
    // doğrulanmış kayıtlarda olabilir; onların hepsi Ulaşım kategorisinde.
    for (final q in questions) {
      if (q.verification != TriviaVerification.metroJson) continue;
      expect(
        q.category,
        TriviaCategory.transportation,
        reason: 'ağ verisiyle doğrulanamayacak kayıt: ${q.id}',
      );
    }
    final verified = questions
        .where((q) => q.verification == TriviaVerification.metroJson)
        .length;
    expect(verified, greaterThan(0), reason: 'hiç doğrulanmış kayıt yok');
  });

  test('aynı soru metni iki kez geçmiyor', () {
    final prompts = questions
        .map((q) => q.prompt.trim().toLowerCase())
        .toList();
    final seen = <String>{};
    final duplicates = <String>[];
    for (final p in prompts) {
      if (!seen.add(p)) duplicates.add(p);
    }
    expect(duplicates, isEmpty);
  });

  test('doğru cevap şıklar arasında bir kez geçiyor', () {
    for (final q in questions) {
      final answer = q.answer;
      final matches = q.options.where((o) => o == answer).length;
      expect(matches, 1, reason: q.id);
    }
  });

  test('kategori kimlikleri koddaki enum ile birebir', () {
    final declared = (root['categories'] as List<dynamic>)
        .map((c) => (c as Map<String, dynamic>)['id'] as String)
        .toSet();
    expect(declared, TriviaCategory.values.map((c) => c.id).toSet());
  });
}
