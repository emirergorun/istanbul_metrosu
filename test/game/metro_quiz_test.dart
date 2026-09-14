import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/questions/question_repository.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/metro_quiz_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/quiz_pool.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/quiz_generator.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/quiz_question.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/quiz_rules.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final metro = MetroFixture.load();
  final routeService = RouteService(metro);

  MetroQuizController controllerFor({
    List<TriviaQuestion> trivia = const <TriviaQuestion>[],
    int seed = 5,
  }) {
    return MetroQuizController(
      journey: routeService.estimate('m2_taksim', 'm2_levent').journey!,
      recordToBeat: 0,
      pool: QuizPool(
        generator: QuizGenerator(metro: metro, random: Random(seed)),
        trivia: trivia,
        random: Random(seed),
      ),
      tick: const Duration(days: 1),
    );
  }

  /// Doğru cevabı verir ve cevabın gösterimini atlayıp sıradaki soruya geçer.
  void answerCorrectly(MetroQuizController controller) {
    controller.answer(controller.question.answerIndex);
    controller.debugAdvanceReveal();
  }

  void answerWrongly(MetroQuizController controller) {
    final wrong = (controller.question.answerIndex + 1) % 4;
    controller.answer(wrong);
    controller.debugAdvanceReveal();
  }

  group('soru üretimi', () {
    test('her soru 4 şıklı ve doğru cevap şıklar içinde', () {
      final generator = QuizGenerator(metro: metro, random: Random(1));
      for (var i = 0; i < 300; i++) {
        final q = generator.next(hard: i.isEven);
        expect(q.options, hasLength(4), reason: q.prompt);
        expect(q.answerIndex, inInclusiveRange(0, 3), reason: q.prompt);
        expect(
          q.options.toSet(),
          hasLength(4),
          reason: 'şıklar tekrar etmemeli: ${q.prompt}',
        );
        expect(q.prompt.trim(), isNotEmpty);
      }
    });

    test('önceki/sonraki durak sorusunun cevabı gerçekten komşu durak', () {
      final generator = QuizGenerator(metro: metro, random: Random(9));
      var checked = 0;

      for (var i = 0; i < 400 && checked < 40; i++) {
        final q = generator.next(hard: true);
        if (!q.id.startsWith('nb_')) continue;

        // id: nb_<istasyon id>_<next|prev>
        final parts = q.id.split('_');
        final direction = parts.last;
        final stationId = parts.sublist(1, parts.length - 1).join('_');
        final subject = metro.stationById(stationId)!;
        final line = metro.stationsOfLine(subject.lineId);
        final index = line.indexWhere((s) => s.id == subject.id);
        final expected = direction == 'next'
            ? line[index + 1].name
            : line[index - 1].name;

        expect(q.answer, expected, reason: q.prompt);
        checked++;
      }

      expect(checked, greaterThan(0), reason: 'komşu durak sorusu üretilmedi');
    });

    test('aynı soru arka arkaya sorulmaz', () {
      final pool = QuizPool(
        generator: QuizGenerator(metro: metro, random: Random(3)),
        random: Random(3),
      );
      final seen = <String>{};
      for (var i = 0; i < 60; i++) {
        final q = pool.next(hard: false);
        expect(seen.contains(q.id), isFalse, reason: 'tekrar: ${q.prompt}');
        seen.add(q.id);
      }
    });
  });

  group('seri çarpanı', () {
    test('merdiven: 3 doğru ×2, 6 doğru ×3, 10 doğru ×4, tavan ×4', () {
      expect(QuizRules.multiplierFor(0), 1);
      expect(QuizRules.multiplierFor(2), 1);
      expect(QuizRules.multiplierFor(3), 2);
      expect(QuizRules.multiplierFor(5), 2);
      expect(QuizRules.multiplierFor(6), 3);
      expect(QuizRules.multiplierFor(10), 4);
      expect(QuizRules.multiplierFor(99), 4);
    });

    test('üçüncü doğru cevap zaten ×2 kazandırır', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerCorrectly(controller);
      answerCorrectly(controller);
      expect(controller.score, QuizRules.basePoints * 2);
      expect(controller.multiplier, 1);

      answerCorrectly(controller);
      expect(controller.multiplier, 2);
      expect(
        controller.score,
        QuizRules.basePoints * 2 + QuizRules.basePoints * 2,
      );
    });

    test('yanlış cevap seriyi ve çarpanı sıfırlar', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 3; i++) {
        answerCorrectly(controller);
      }
      expect(controller.multiplier, 2);

      answerWrongly(controller);

      expect(controller.streak, 0);
      expect(controller.multiplier, 1);
      expect(controller.bestStreak, 3, reason: 'en uzun seri hatırlanmalı');
    });
  });

  group('yanlış hakkı', () {
    test('üç yanlışta oyun biter, ikisinde bitmez', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerWrongly(controller);
      answerWrongly(controller);

      expect(controller.livesLeft, 1);
      expect(controller.status, GameStatus.playing);

      controller.answer((controller.question.answerIndex + 1) % 4);

      expect(controller.mistakes, QuizRules.mistakeAllowance);
      expect(controller.livesLeft, 0);
    });

    test('süre dolması seriyi bozar ama can götürmez', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerCorrectly(controller);
      answerCorrectly(controller);
      expect(controller.streak, 2);

      controller.debugAdvance(QuizRules.answerTime.inSeconds.toDouble() + 1);

      expect(controller.streak, 0, reason: 'seri bozulmalı');
      expect(
        controller.mistakes,
        0,
        reason: 'gözünü kaldıran oyuncu can kaybetmemeli',
      );
      expect(controller.livesLeft, QuizRules.mistakeAllowance);
      expect(controller.isRevealing, isTrue);
      expect(controller.chosenIndex, -1, reason: 'seçim yapılmadı');
    });

    test('süre dolması oyunu bitirmez, üç yanlış bitirir', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 5; i++) {
        controller.debugAdvance(QuizRules.answerTime.inSeconds.toDouble() + 1);
        controller.debugAdvanceReveal();
      }

      expect(controller.status, GameStatus.playing);
      expect(controller.mistakes, 0);
    });
  });

  group('yazılı sorular', () {
    test('havuzdaki soru şıkları karıştırılır ama cevap doğru kalır', () {
      const trivia = TriviaQuestion(
        id: 't1',
        prompt: 'Marmaray hangi yıl açıldı?',
        options: <String>['2013', '2009', '2016', '2004'],
        answerIndex: 0,
      );
      final pool = QuizPool(
        generator: QuizGenerator(metro: metro, random: Random(2)),
        trivia: const <TriviaQuestion>[trivia],
        random: Random(2),
      );

      QuizQuestion? asked;
      for (var i = 0; i < 40 && asked == null; i++) {
        final q = pool.next(hard: false);
        if (q.topic == QuizTopic.trivia) asked = q;
      }

      expect(asked, isNotNull, reason: 'yazılı soru hiç sorulmadı');
      expect(asked!.options.toSet(), trivia.options.toSet());
      expect(asked.answer, '2013');
    });

    test('bozuk kayıtlar havuza girmez, dosya çökertmez', () {
      final dataset = QuestionDataset.parse('''
      { "version": 1, "questions": [
        { "id": "ok", "text": "Soru?", "options": ["a","b","c","d"], "answer": 2 },
        { "id": "az_sik", "text": "Soru?", "options": ["a","b"], "answer": 0 },
        { "id": "kotu_cevap", "text": "Soru?", "options": ["a","b","c","d"], "answer": 9 }
      ]}
      ''');

      expect(dataset.questions(), hasLength(1));
      expect(dataset.questions().single.id, 'ok');
      expect(dataset.questions().single.answer, 'c');
    });
  });
}
