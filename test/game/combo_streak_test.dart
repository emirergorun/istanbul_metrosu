import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/constants/app_constants.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/combo.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/streak.dart';

/// Ardışık hamleleri tek satırda kurmak için.
ComboState _combo(List<bool> moves) {
  var state = const ComboState();
  for (final didClear in moves) {
    state = state.register(didClear: didClear);
  }
  return state;
}

StreakState _streak(List<bool> moves) {
  var state = const StreakState();
  for (final didClear in moves) {
    state = state.register(didClear: didClear);
  }
  return state;
}

void main() {
  group('ComboState', () {
    test('başlangıçta combo yok', () {
      const state = ComboState();
      expect(state.value, 0);
      expect(state.isActive, isFalse);
      expect(state.graceLeft, 0);
    });

    test('her temizlik combo’yu bir artırır', () {
      expect(_combo(<bool>[true]).value, 1);
      expect(_combo(<bool>[true, true]).value, 2);
      expect(_combo(<bool>[true, true, true]).value, 3);
    });

    test('hazırlık hamlesi combo’yu düşürmez', () {
      final state = _combo(<bool>[true, true, false]);
      expect(state.value, 2);
      expect(state.isActive, isTrue);
      expect(state.movesSinceLastClear, 1);
    });

    test('pay kadar hazırlık hamlesi combo’yu yaşatır', () {
      final moves = <bool>[
        true,
        for (var i = 0; i < ScoreRules.comboGraceMoves; i++) false,
      ];
      expect(_combo(moves).value, 1);
    });

    test('pay aşılınca combo sıfırlanır', () {
      final moves = <bool>[
        true,
        for (var i = 0; i < ScoreRules.comboGraceMoves + 1; i++) false,
      ];
      final state = _combo(moves);

      expect(state.value, 0);
      expect(state.isActive, isFalse);
      expect(state.best, 1, reason: 'en iyi combo sıfırlanmaz');
    });

    test('hazırlıktan sonra temizlik combo’yu sürdürür', () {
      final state = _combo(<bool>[true, true, false, true]);
      expect(state.value, 3);
      expect(state.movesSinceLastClear, 0);
    });

    test('temizlik hazırlık sayacını sıfırlar', () {
      final state = _combo(<bool>[true, false, true, false]);
      expect(state.movesSinceLastClear, 1);
      expect(state.graceLeft, ScoreRules.comboGraceMoves - 1);
    });

    test('combo yokken hazırlık hamleleri durumu değiştirmez', () {
      const start = ComboState();
      expect(start.register(didClear: false), start);
    });

    test('en iyi combo oturum boyunca korunur', () {
      final state = _combo(<bool>[
        true,
        true,
        true,
        for (var i = 0; i < ScoreRules.comboGraceMoves + 1; i++) false,
        true,
      ]);

      expect(state.value, 1);
      expect(state.best, 3);
    });
  });

  group('StreakState', () {
    test('tepsi dolmadan streak değişmez', () {
      final state = _streak(<bool>[true]);
      expect(state.value, 0);
      expect(state.piecesInSet, 1);
      expect(state.clearedInSet, isTrue);
    });

    test('temizlikli tepsi streak’i artırır', () {
      final state = _streak(<bool>[false, true, false]);
      expect(state.value, 1);
      expect(state.piecesInSet, 0, reason: 'yeni tepsi sıfırdan başlar');
      expect(state.clearedInSet, isFalse);
    });

    test('temizliksiz tepsi streak’i sıfırlar', () {
      final built = _streak(<bool>[
        true,
        false,
        false,
        // ikinci tepsi hiç temizlemiyor
        false,
        false,
        false,
      ]);

      expect(built.value, 0);
      expect(built.best, 1);
    });

    test('art arda temizlikli tepsiler streak’i büyütür', () {
      final state = _streak(<bool>[
        for (var set = 0; set < 3; set++) ...<bool>[false, false, true],
      ]);

      expect(state.value, 3);
      expect(state.best, 3);
    });

    test('tepsi boyutu sabitten okunur', () {
      var state = const StreakState();
      for (var i = 0; i < AppConstants.traySize - 1; i++) {
        state = state.register(didClear: true);
        expect(state.value, 0, reason: 'tepsi henüz kapanmadı');
      }
      state = state.register(didClear: true);
      expect(state.value, 1);
    });

    test('kalan parça sayısı doğru', () {
      final state = _streak(<bool>[true]);
      expect(state.piecesLeftInSet, AppConstants.traySize - 1);
    });

    test('en iyi streak sıfırlanmayla kaybolmaz', () {
      final state = _streak(<bool>[
        for (var set = 0; set < 2; set++) ...<bool>[true, false, false],
        false,
        false,
        false,
      ]);

      expect(state.value, 0);
      expect(state.best, 2);
    });
  });
}
