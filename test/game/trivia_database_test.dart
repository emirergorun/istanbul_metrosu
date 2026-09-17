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

  test('havuz en az 1.200 soru taşıyor ve tamamı ayrıştırılıyor', () {
    final items = root['questions'] as List<dynamic>;
    expect(items.length, greaterThanOrEqualTo(1200));
    expect(
      questions,
      hasLength(items.length),
      reason: 'ayrıştırma hiçbir kaydı elemeden geçmeli',
    );
  });

  test('her kategoride en az 150 soru var', () {
    // Kategori başına **eşit** sayı aranmıyor: İstanbul bilinçli olarak
    // kalabalık (oyunun konusu bu şehir), Tarih ise çok zor yıl-ezberi
    // soruları silindiği için küçüldü.
    for (final category in TriviaCategory.values) {
      expect(
        dataset.byCategory(category).length,
        greaterThanOrEqualTo(150),
        reason: category.id,
      );
    }
  });

  test('İstanbul kategorisi havuzun en kalabalık kategorisi', () {
    final counts = <int>[
      for (final c in TriviaCategory.values) dataset.byCategory(c).length,
    ];
    expect(
      dataset.byCategory(TriviaCategory.istanbul).length,
      counts.reduce((a, b) => a > b ? a : b),
      reason: 'oyunun konusu İstanbul; havuz bunu yansıtmalı',
    );
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
    // doğrulanmış kayıtlarda olabilir; onların hepsi İstanbul kategorisinde.
    for (final q in questions) {
      if (q.verification != TriviaVerification.metroJson) continue;
      expect(
        q.category,
        TriviaCategory.istanbul,
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
