import 'dart:math';

import '../../../../data/questions/question_repository.dart';
import '../domain/quiz_generator.dart';
import '../domain/quiz_question.dart';

/// Bir yolculuğun soru akışı: üretilen ağ soruları + yazılı bilgi soruları.
///
/// Karışım oranı sabit değil, **havuzun durumuna** bağlı. Yazılı sorular
/// sınırlı (birkaç yüz), üretilenler tükenmiyor; bu yüzden yazılı soru
/// kalmadığında akış kendiliğinden üretilene düşer ve oyun soru bulamadığı
/// için durmaz.
///
/// 12 dakikalık bir yolculuk ~60 soru demek: yazılı havuz tek başına bir
/// yolculuğu bile zor doldurur, omurga her zaman üretilen sorulardır.
class QuizPool {
  QuizPool({
    required QuizGenerator generator,
    List<TriviaQuestion> trivia = const <TriviaQuestion>[],
    Random? random,
    // Alan private, parametre public kalmalı; `this._generator` dışarıdan
    // kullanılamayacak bir ad üretirdi.
    // ignore: prefer_initializing_formals
  }) : _generator = generator,
       _random = random ?? Random(),
       _trivia = List<TriviaQuestion>.of(trivia) {
    _trivia.shuffle(_random);
  }

  /// Yazılı sorunun seçilme olasılığı (%). Kalanı üretilen sorudur.
  static const int triviaShare = 40;

  final QuizGenerator _generator;
  final Random _random;
  final List<TriviaQuestion> _trivia;

  int _triviaCursor = 0;
  final Set<String> _used = <String>{};

  /// Yolculukta şimdiye kadar sorulan soru sayısı.
  int get askedCount => _used.length;

  /// Yeniden başlatmada havuzu tazeler: sorulmuşlar unutulur, yazılı
  /// sorular yeniden karışır.
  void reset() {
    _used.clear();
    _triviaCursor = 0;
    _trivia.shuffle(_random);
  }

  /// Sıradaki soru.
  ///
  /// [hard] çeldiricilerin zorluğunu belirler; oyun bunu seriye göre verir,
  /// yolculuk uzunluğuna göre değil.
  QuizQuestion next({required bool hard}) {
    final wantsTrivia =
        _triviaCursor < _trivia.length && _random.nextInt(100) < triviaShare;

    final question = wantsTrivia
        ? _fromTrivia(_trivia[_triviaCursor++])
        : _generator.next(hard: hard, usedIds: _used);

    _used.add(question.id);
    return question;
  }

  /// Yazılı soruyu oyuna verirken şıkları karıştırır.
  ///
  /// Dosyada doğru cevap hep aynı sırada olabilir; karıştırmazsak oyuncu
  /// bir süre sonra soruyu değil, şıkkın yerini öğrenir.
  QuizQuestion _fromTrivia(TriviaQuestion source) {
    final options = List<String>.of(source.options)..shuffle(_random);
    return QuizQuestion(
      id: source.id,
      prompt: source.prompt,
      options: List<String>.unmodifiable(options),
      answerIndex: options.indexOf(source.answer),
      topic: QuizTopic.trivia,
      context: source.context,
    );
  }
}
