import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_progress_controller.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_progress.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Yıldız', () {
    test('sınırlara göre üç, iki, bir yıldız', () {
      int stars(int moves) => EscapeRules.starsFor(
        moves: moves,
        threeStarMoves: 8,
        twoStarMoves: 12,
      );
      expect(stars(7), 3);
      expect(stars(8), 3);
      expect(stars(9), 2);
      expect(stars(12), 2);
      expect(stars(13), 1);
      expect(stars(80), 1, reason: 'her bitiriş en az bir yıldız');
    });

    test('ipucu alınan denemede üçüncü yıldız yok', () {
      expect(
        EscapeRules.starsFor(
          moves: 8,
          threeStarMoves: 8,
          twoStarMoves: 12,
          usedHint: true,
        ),
        2,
      );
      expect(
        EscapeRules.starsFor(
          moves: 20,
          threeStarMoves: 8,
          twoStarMoves: 12,
          usedHint: true,
        ),
        1,
      );
    });

    test('sınırlar en kısa çözümden türer ve tutarlı', () {
      for (var optimal = 1; optimal <= 50; optimal++) {
        for (final branching in <double>[2, 8, 20]) {
          final (three, two) = EscapeRules.parFor(
            optimal: optimal,
            branching: branching,
          );
          expect(three, greaterThanOrEqualTo(optimal));
          expect(two, greaterThan(three));
          // Kısa bölümde üç yıldız kusursuz çözüm demek.
          if (optimal < 12) expect(three, optimal);
        }
      }
    });
  });

  group('Yolculuk puanı', () {
    test('ilk bitiriş tam puan, yıldız çarpanıyla', () {
      final one = EscapeRules.journeyPoints(
        optimal: 10,
        stars: 1,
        previousBestStars: 0,
        alreadyCreditedThisJourney: false,
      );
      final three = EscapeRules.journeyPoints(
        optimal: 10,
        stars: 3,
        previousBestStars: 0,
        alreadyCreditedThisJourney: false,
      );
      expect(one, EscapeRules.basePoints(10));
      expect(three, greaterThan(one));
    });

    test('zor bölüm kolaydan çok puan verir', () {
      int full(int optimal) => EscapeRules.journeyPoints(
        optimal: optimal,
        stars: 2,
        previousBestStars: 0,
        alreadyCreditedThisJourney: false,
      );
      expect(full(20), greaterThan(full(5)));
    });

    test('tekrar oynayarak puan kasılamaz', () {
      // Aynı yıldızla tekrar: yolculukta bir kez küçük pay, sonra sıfır.
      final firstReplay = EscapeRules.journeyPoints(
        optimal: 6,
        stars: 3,
        previousBestStars: 3,
        alreadyCreditedThisJourney: false,
      );
      final secondReplay = EscapeRules.journeyPoints(
        optimal: 6,
        stars: 3,
        previousBestStars: 3,
        alreadyCreditedThisJourney: true,
      );
      expect(firstReplay, greaterThan(0));
      expect(
        firstReplay,
        lessThan(EscapeRules.fullPoints(optimal: 6, stars: 3)),
      );
      expect(secondReplay, 0);
    });

    test('yıldız artışı yalnız farkı kazandırır', () {
      final improved = EscapeRules.journeyPoints(
        optimal: 10,
        stars: 3,
        previousBestStars: 1,
        alreadyCreditedThisJourney: true,
      );
      expect(
        improved,
        EscapeRules.fullPoints(optimal: 10, stars: 3) -
            EscapeRules.fullPoints(optimal: 10, stars: 1),
      );
    });
  });

  group('Bölüm kaydı', () {
    test('ilk bölüm açık, sonraki kilitli', () {
      const progress = EscapeProgress.empty;
      expect(progress.isUnlocked(1), isTrue);
      expect(progress.isUnlocked(2), isFalse);
      expect(progress.nextLevel(60), 1);
    });

    test('bitirmek bir sonrakini açar', () {
      final progress = EscapeProgress.empty.withCompletion(
        level: 1,
        moves: 3,
        stars: 2,
        perfect: false,
      );
      expect(progress.isCompleted(1), isTrue);
      expect(progress.isUnlocked(2), isTrue);
      expect(progress.isUnlocked(3), isFalse);
      expect(progress.nextLevel(60), 2);
    });

    test('daha kötü sonuç daha iyisinin üstüne yazılmaz', () {
      var progress = EscapeProgress.empty.withCompletion(
        level: 4,
        moves: 5,
        stars: 3,
        perfect: false,
      );
      progress = progress.withCompletion(
        level: 4,
        moves: 11,
        stars: 1,
        perfect: false,
      );
      final record = progress.recordOf(4)!;
      expect(record.bestMoves, 5);
      expect(record.bestStars, 3);
      expect(record.wins, 2);
    });

    test('her alan kendi en iyisini korur', () {
      var progress = EscapeProgress.empty.withCompletion(
        level: 7,
        moves: 9,
        stars: 1,
        perfect: false,
      );
      // Daha az hamle ama ipucuyla: hamle iyileşir, yıldız da.
      progress = progress.withCompletion(
        level: 7,
        moves: 8,
        stars: 2,
        perfect: false,
      );
      progress = progress.withCompletion(
        level: 7,
        moves: 12,
        stars: 1,
        perfect: true,
      );
      final record = progress.recordOf(7)!;
      expect(record.bestMoves, 8);
      expect(record.bestStars, 2);
      expect(record.perfect, isTrue);
    });

    test('toplamlar', () {
      var progress = EscapeProgress.empty;
      progress = progress.withCompletion(
        level: 1,
        moves: 2,
        stars: 3,
        perfect: false,
      );
      progress = progress.withCompletion(
        level: 2,
        moves: 5,
        stars: 2,
        perfect: false,
      );
      progress = progress.withCompletion(
        level: 3,
        moves: 14,
        stars: 3,
        perfect: true,
      );
      expect(progress.completedCount, 3);
      expect(progress.totalStars, 8);
      expect(progress.masteredCount, 2);
      expect(progress.perfectCount, 1);
    });

    test('kodlanıp çözülünce aynı kayıt', () {
      var progress = EscapeProgress.empty;
      for (var level = 1; level <= 12; level++) {
        progress = progress.withCompletion(
          level: level,
          moves: level + 2,
          stars: 1 + level % 3,
          perfect: level.isEven,
        );
      }
      expect(EscapeProgress.decode(progress.encode()), progress);
    });

    test('bozuk kayıt boş ilerleme döner, sağlam bölümler korunur', () {
      expect(EscapeProgress.decode('{bozuk'), EscapeProgress.empty);
      expect(EscapeProgress.decode('[]'), EscapeProgress.empty);
      final partial = EscapeProgress.decode(
        '{"v":1,"levels":{"1":{"m":2,"s":3,"w":1},'
        '"2":{"m":"x","s":2},"x":{"m":3,"s":1},"3":{"m":4,"s":9}}}',
      );
      expect(partial.completedCount, 1);
      expect(partial.recordOf(1)!.bestStars, 3);
    });
  });

  group('Kayıt kalıcılığı', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'bitiriş kaydedilir ve uygulama yeniden açılınca geri gelir',
      () async {
        final store = LocalStore();
        await store.init();
        final controller = EscapeProgressController(store: store);

        final result = controller.record(
          level: 1,
          moves: 2,
          stars: 3,
          perfect: false,
        );
        expect(result.isFirstCompletion, isTrue);
        expect(result.unlockedNext, isTrue);
        await controller.flush();

        // Uygulama kapanıp açıldı: yeni depo, yeni denetleyici.
        final reopened = LocalStore();
        await reopened.init();
        final restored = EscapeProgressController(store: reopened);
        expect(restored.isCompleted(1), isTrue);
        expect(restored.isUnlocked(2), isTrue);
        expect(restored.recordOf(1)!.bestMoves, 2);
        expect(restored.totalStars, 3);
      },
    );

    test(
      'kötü tekrar kayıttaki en iyiyi bozmaz, kilidi geri kapatmaz',
      () async {
        final store = LocalStore();
        await store.init();
        final controller = EscapeProgressController(store: store)
          ..record(level: 1, moves: 2, stars: 3, perfect: false);
        final again = controller.record(
          level: 1,
          moves: 9,
          stars: 1,
          perfect: false,
        );
        expect(again.isFirstCompletion, isFalse);
        expect(again.unlockedNext, isFalse);
        expect(again.isNewBestFor(9), isFalse);
        expect(controller.recordOf(1)!.bestMoves, 2);
        expect(controller.isUnlocked(2), isTrue);
      },
    );

    test('kilitli bölüm kaydedilemez', () {
      final controller = EscapeProgressController();
      expect(
        () => controller.record(level: 5, moves: 3, stars: 1, perfect: false),
        throwsStateError,
      );
    });
  });
}
