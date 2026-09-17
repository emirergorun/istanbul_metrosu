import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/questions/question_repository.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/metro_quiz_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/quiz_pool.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/quiz_rules.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/trivia_category.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';
import '../helpers/trivia_fixture.dart';

void main() {
  final metro = MetroFixture.load();
  final routeService = RouteService(metro);

  MetroQuizController controllerFor({
    QuestionRepository? repository,
    int seed = 5,
  }) {
    return MetroQuizController(
      journey: routeService.estimate('m2_taksim', 'm2_levent').journey!,
      recordToBeat: 0,
      pool: QuizPool(
        repository: repository ?? TriviaFixture.repository(),
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

  group('soru akışı', () {
    test('her soru 4 şıklı ve doğru cevap şıklar içinde', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 100; i++) {
        final q = controller.question;
        expect(q.options, hasLength(4), reason: q.id);
        expect(q.answerIndex, inInclusiveRange(0, 3), reason: q.id);
        expect(q.options.toSet(), hasLength(4), reason: q.id);
        expect(q.prompt.trim(), isNotEmpty, reason: q.id);
        answerCorrectly(controller);
      }
    });

    test('aynı soru bir yolculukta iki kez sorulmaz', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      final seen = <String>{controller.question.id};
      for (var i = 0; i < 150; i++) {
        answerCorrectly(controller);
        expect(
          seen.add(controller.question.id),
          isTrue,
          reason: 'tekrar eden soru: ${controller.question.id}',
        );
      }
    });

    test('üst üste aynı kategoriden ikiden fazla soru gelmez', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      var streak = 1;
      var previous = controller.question.category;
      for (var i = 0; i < 200; i++) {
        answerCorrectly(controller);
        final current = controller.question.category;
        streak = current == previous ? streak + 1 : 1;
        previous = current;
        expect(
          streak,
          lessThanOrEqualTo(QuizPool.maxSameCategoryStreak),
          reason: '$streak kez üst üste ${current.id}',
        );
      }
    });

    test('her sorunun kategorisi taşınıyor', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 20; i++) {
        expect(TriviaCategory.values, contains(controller.question.category));
        answerCorrectly(controller);
      }
    });

    test('ilk sorular kolay havuzdan gelir', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < QuizPool.warmupQuestions - 1; i++) {
        expect(
          controller.question.difficulty,
          TriviaDifficulty.easy,
          reason: '$i. soru ısınma havuzunda olmalı',
        );
        answerCorrectly(controller);
      }
    });

    test('havuz tükenirse oyun durmaz', () {
      // Üç soruluk bir havuzda dördüncü soru da gelmeli.
      final controller = controllerFor(
        repository: TriviaFixture.repository(perCategory: 1),
      )..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 30; i++) {
        expect(controller.question.options, hasLength(4));
        answerCorrectly(controller);
      }
    });

    test('havuz boşsa oyun açılmaz yerine boş soruyla çökmez', () {
      expect(
        () => controllerFor(repository: const EmptyQuestionRepository()),
        throwsA(anything),
        reason: 'boş havuz sessizce boş soru üretmemeli; hata görünür olmalı',
      );
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

      // Hız bonusu puana karışmasın diye sayacın yarısı tüketiliyor:
      // bonus yalnızca yarıdan fazlası kalmışsa verilir.
      void slowCorrect() {
        controller.debugAdvance(controller.questionDuration * 0.6);
        answerCorrectly(controller);
      }

      slowCorrect();
      slowCorrect();
      expect(controller.score, QuizRules.basePoints * 2);
      expect(controller.multiplier, 1);

      slowCorrect();
      expect(controller.multiplier, 2);
      expect(
        controller.score,
        QuizRules.basePoints * 2 + QuizRules.basePoints * 2,
      );
    });

    test('hızlı cevap ek puan kazandırır, yavaş cevap kazandırmaz', () {
      final fast = controllerFor()..start();
      addTearDown(fast.dispose);
      final slow = controllerFor()..start();
      addTearDown(slow.dispose);

      answerCorrectly(fast);
      slow.debugAdvance(slow.questionDuration * 0.7);
      answerCorrectly(slow);

      expect(fast.score, greaterThan(slow.score));
      expect(fast.lastSpeedBonus, greaterThan(0));
      expect(slow.lastSpeedBonus, 0);
      expect(fast.lastSpeedBonus, lessThanOrEqualTo(QuizRules.speedBonusMax));
    });

    test('beş doğruluk seri joker kazandırır', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      controller.useJoker();
      expect(controller.jokersLeft, 0);

      for (var i = 0; i < QuizRules.jokerRewardStreak; i++) {
        answerCorrectly(controller);
      }
      expect(controller.jokersLeft, 1);
    });

    test('joker tavanı aşılmaz', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < QuizRules.jokerRewardStreak * 4; i++) {
        answerCorrectly(controller);
      }
      expect(controller.jokersLeft, lessThanOrEqualTo(QuizRules.maxJokers));
    });

    test('kaçırılan sorular saklanır', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      final missed = controller.question;
      answerWrongly(controller);

      expect(controller.missedQuestions, contains(missed));
      answerCorrectly(controller);
      expect(controller.missedQuestions, hasLength(1));
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
    test('oyun üç hakla başlar', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      expect(QuizRules.mistakeAllowance, 3);
      expect(controller.livesLeft, 3);
      expect(controller.mistakes, 0);
    });

    test('doğru cevap can götürmez', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 10; i++) {
        answerCorrectly(controller);
      }
      expect(controller.livesLeft, 3);
      expect(controller.status, GameStatus.playing);
    });

    test('her yanlış bir can götürür', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerWrongly(controller);
      expect(controller.livesLeft, 2);
      answerWrongly(controller);
      expect(controller.livesLeft, 1);
    });

    test('canlar bitince oyun biter', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerWrongly(controller);
      answerWrongly(controller);
      expect(controller.status, GameStatus.playing);

      controller.answer((controller.question.answerIndex + 1) % 4);

      expect(controller.mistakes, QuizRules.mistakeAllowance);
      expect(controller.livesLeft, 0);
    });

    test('aynı soruya ikinci dokunuş ne can götürür ne puan ekler', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      final correct = controller.question.answerIndex;
      final wrong = (correct + 1) % 4;

      expect(controller.answer(correct), isTrue);
      final scoreAfterFirst = controller.score;

      // Çift dokunuş: doğru şıktan hemen sonra yanlış şıkka basmak.
      expect(controller.answer(wrong), isFalse);
      expect(controller.answer(correct), isFalse);

      expect(
        controller.score,
        scoreAfterFirst,
        reason: 'puan iki kez eklenmemeli',
      );
      expect(controller.livesLeft, 3, reason: 'can gitmemeli');
      expect(controller.streak, 1, reason: 'seri bir kez artmalı');
    });

    test('yanlış cevaba ikinci dokunuş ikinci canı götürmez', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      final wrong = (controller.question.answerIndex + 1) % 4;
      expect(controller.answer(wrong), isTrue);
      expect(controller.livesLeft, 2);

      expect(controller.answer(wrong), isFalse);
      expect(controller.answer((wrong + 1) % 4), isFalse);
      expect(controller.livesLeft, 2);
    });

    test('cevap gösterilirken soru atlanmaz', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      final first = controller.question.id;
      controller.answer(controller.question.answerIndex);
      // İkinci dokunuş sıradaki soruya geçmemeli.
      controller.answer(controller.question.answerIndex);
      expect(controller.question.id, first);

      controller.debugAdvanceReveal();
      expect(controller.question.id, isNot(first));
    });

    test('süre dolması hem seriyi bozar hem can götürür', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerCorrectly(controller);
      answerCorrectly(controller);
      expect(controller.streak, 2);

      controller.debugAdvance(QuizRules.answerTime.inSeconds.toDouble() + 1);

      expect(controller.streak, 0, reason: 'seri bozulmalı');
      expect(
        controller.mistakes,
        1,
        reason: 'cevap vermemek de bir cevap: hak gitmeli',
      );
      expect(controller.livesLeft, QuizRules.mistakeAllowance - 1);
      expect(controller.isRevealing, isTrue);
      expect(
        controller.chosenIndex,
        -1,
        reason: 'seçim yapılmadı; doğru şık yine de gösterilir',
      );
    });

    test('üç kez süre dolunca oyun biter', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      for (var i = 0; i < 2; i++) {
        controller.debugAdvance(QuizRules.answerTime.inSeconds.toDouble() + 1);
        controller.debugAdvanceReveal();
      }
      expect(controller.livesLeft, 1);
      expect(controller.status, GameStatus.playing);

      controller.debugAdvance(QuizRules.answerTime.inSeconds.toDouble() + 1);

      expect(controller.mistakes, QuizRules.mistakeAllowance);
      expect(controller.livesLeft, 0);
    });

    test('süre dolması ile yanlış cevap aynı bedele sahip', () {
      final timeout = controllerFor()..start();
      addTearDown(timeout.dispose);
      final wrong = controllerFor()..start();
      addTearDown(wrong.dispose);

      timeout.debugAdvance(QuizRules.answerTime.inSeconds.toDouble() + 1);
      wrong.answer((wrong.question.answerIndex + 1) % 4);

      expect(timeout.livesLeft, wrong.livesLeft);
      expect(timeout.streak, wrong.streak);
      expect(timeout.score, wrong.score);
    });
  });

  group('joker', () {
    test('iki yanlış şıkkı eler, doğruyu elemez', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      expect(controller.jokersLeft, QuizRules.jokerCount);
      expect(controller.useJoker(), isTrue);

      expect(controller.eliminatedOptions, hasLength(2));
      expect(
        controller.eliminatedOptions.contains(controller.question.answerIndex),
        isFalse,
        reason: 'doğru şık asla elenmemeli',
      );
      expect(controller.jokersLeft, 0);
    });

    test('yolculuk başına tek hak', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      expect(controller.useJoker(), isTrue);
      answerCorrectly(controller);
      expect(controller.canUseJoker, isFalse);
      expect(controller.useJoker(), isFalse);
    });

    test('sıradaki soruda eleme temizlenir', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      controller.useJoker();
      expect(controller.eliminatedOptions, isNotEmpty);
      answerCorrectly(controller);
      expect(controller.eliminatedOptions, isEmpty);
    });

    test('aynı soruda joker iki kez çalışmaz', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      expect(controller.useJoker(), isTrue);
      expect(controller.useJoker(), isFalse);
      expect(controller.eliminatedOptions, hasLength(2));
    });

    test('yeniden başlatmada joker geri gelir', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      controller.useJoker();
      controller.restart();
      expect(controller.jokersLeft, QuizRules.jokerCount);
      expect(controller.eliminatedOptions, isEmpty);
    });
  });

  group('zorluğa göre süre', () {
    test('zor soru daha uzun sürer', () {
      expect(
        QuizRules.answerTimeFor(TriviaDifficulty.hard),
        QuizRules.answerTime + QuizRules.hardQuestionBonus,
      );
      expect(
        QuizRules.answerTimeFor(TriviaDifficulty.easy),
        QuizRules.answerTime,
      );
      expect(
        QuizRules.answerTimeFor(TriviaDifficulty.medium),
        QuizRules.answerTime,
      );
    });

    test('sayaç sorunun kendi süresiyle başlar', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      expect(
        controller.questionRemaining,
        QuizRules.answerTimeFor(controller.question.difficulty).inSeconds,
      );
      expect(controller.questionProgress, 1.0);
    });

    test('son saniyelerde aciliyet bayrağı kalkar', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      expect(controller.isUrgent, isFalse);
      controller.debugAdvance(
        controller.questionDuration - QuizRules.urgentSeconds + 0.5,
      );
      expect(controller.isUrgent, isTrue);
    });
  });

  group('kategori kırılımı', () {
    test('doğru cevaplar kategoriye yazılır', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      final first = controller.question.category;
      answerCorrectly(controller);

      expect(controller.correctByCategory[first], 1);
      expect(controller.askedByCategory[first], greaterThanOrEqualTo(1));
      expect(controller.bestCategory, first);
    });

    test('hiç doğru yoksa en iyi kategori yok', () {
      final controller = controllerFor()..start();
      addTearDown(controller.dispose);

      answerWrongly(controller);
      expect(controller.bestCategory, isNull);
    });
  });

  group('veri ayrıştırma', () {
    test('bozuk kayıtlar havuza girmez, dosya çökertmez', () {
      final dataset = QuestionDataset.parse('''
      { "schemaVersion": 2, "questions": [
        { "id": "ok", "category": "history", "difficulty": "easy",
          "question": "Soru?", "options": ["a","b","c","d"],
          "correctAnswerIndex": 2, "source": "https://x/",
          "verification": "model_knowledge" },
        { "id": "az_sik", "category": "history", "difficulty": "easy",
          "question": "Soru?", "options": ["a","b"],
          "correctAnswerIndex": 0, "source": "https://x/",
          "verification": "model_knowledge" },
        { "id": "kotu_cevap", "category": "history", "difficulty": "easy",
          "question": "Soru?", "options": ["a","b","c","d"],
          "correctAnswerIndex": 9, "source": "https://x/",
          "verification": "model_knowledge" },
        { "id": "bilinmeyen_kategori", "category": "uzay", "difficulty": "easy",
          "question": "Soru?", "options": ["a","b","c","d"],
          "correctAnswerIndex": 0, "source": "https://x/",
          "verification": "model_knowledge" }
      ]}
      ''');

      expect(dataset.questions(), hasLength(1));
      expect(dataset.questions().single.id, 'ok');
      expect(dataset.questions().single.answer, 'c');
    });
  });
}
