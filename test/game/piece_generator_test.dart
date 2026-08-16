import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/constants/app_constants.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';

import '../helpers/board_helpers.dart';

void main() {
  group('PieceGenerator', () {
    test('tepsi her zaman 3 parça üretir', () {
      final generator = PieceGenerator(random: Random(7));
      final tray = generator.generateTray(
        Board.empty(),
        DifficultyProfiles.standard,
      );

      expect(tray.length, AppConstants.traySize);
    });

    test('üretilen parçalara renk atanır', () {
      final generator = PieceGenerator(random: Random(7));
      final tray = generator.generateTray(
        Board.empty(),
        DifficultyProfiles.mini,
      );

      for (final piece in tray) {
        expect(piece.colorIndex, greaterThan(0));
      }
    });

    test('renk sayısı palet boyutunu aşmaz', () {
      // Regresyon: generator 6 renk üretiyordu ama palet 5 renk. Fazlalık
      // `forCellValue` içinde başa dönüp ilk rengi iki kat sık gösteriyordu
      // (ölçüm: turuncu 1985, diğerleri ~1000).
      expect(
        AppConstants.blockColorCount,
        AppColors.blocks.length,
        reason: 'sabit ile palet ayrışmış',
      );

      final generator = PieceGenerator(random: Random(7));
      final seen = <int>{};
      for (var i = 0; i < 4000; i++) {
        seen.add(generator.nextPiece(DifficultyProfiles.mini).colorIndex);
      }

      expect(seen.length, AppColors.blocks.length);
      expect(
        seen.map(AppColors.forCellValue).toSet().length,
        seen.length,
        reason: 'iki renk indeksi aynı ekran rengine düşüyor',
      );
    });

    test('fairness: dar board’da bile en az bir legal hamle bulunur', () {
      final generator = PieceGenerator(random: Random(3));

      // Sadece 3 hücrelik boşluk kalmış board.
      final board = boardFrom(<String>[
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXX...',
      ]);

      for (var i = 0; i < 50; i++) {
        final tray = generator.generateTray(board, DifficultyProfiles.marathon);
        expect(
          hasAnyLegalMove(board, tray),
          isTrue,
          reason: 'Tepside oynanabilir parça yok (deneme $i)',
        );
      }
    });

    test('torba: aynı tepside şekil tekrar etmez', () {
      final generator = PieceGenerator(random: Random(5));
      for (var i = 0; i < 300; i++) {
        final tray = generator.generateTray(
          Board.empty(),
          DifficultyProfiles.standard,
        );
        expect(
          tray.map((p) => p.id).toSet().length,
          tray.length,
          reason: 'tepsi $i içinde tekrar eden şekil var',
        );
      }
    });

    test('torba: havuzdaki her şekil görünür', () {
      // Torbasız ağırlıklı random'da zor şekiller %1 sıklıkla çıkıyordu;
      // torba her şeklin sırası gelmesini garanti eder.
      final generator = PieceGenerator(random: Random(9));
      final seen = <String>{};
      for (var i = 0; i < 400; i++) {
        for (final piece in generator.generateTray(
          Board.empty(),
          DifficultyProfiles.marathon,
        )) {
          seen.add(piece.id);
        }
      }
      expect(seen.length, PieceShapes.all.length);
    });

    test('aynı seed aynı tepsiyi üretir (deterministik)', () {
      final first = PieceGenerator(
        random: Random(99),
      ).generateTray(Board.empty(), DifficultyProfiles.standard);
      final second = PieceGenerator(
        random: Random(99),
      ).generateTray(Board.empty(), DifficultyProfiles.standard);

      expect(first.map((p) => p.id).toList(), second.map((p) => p.id).toList());
    });

    test('hardPieceWeight zor parça sıklığını belirler', () {
      // Mekanizma testi: ağırlık arttıkça zor parça artmalı. Hangi profilin
      // daha zor olduğu ayrı bir karar (bkz. "zorluk ters orantılı" grubu).
      int hardCount(double weight) {
        final profile = DifficultyProfile(
          id: 'w$weight',
          label: 'w',
          minMinutes: 0,
          maxMinutes: null,
          initialBlockerRatio: 0,
          hardPieceWeight: weight,
          undoCount: 0,
        );
        final generator = PieceGenerator(random: Random(11));
        var count = 0;
        for (var i = 0; i < 400; i++) {
          if (generator.nextPiece(profile).difficulty.name == 'hard') count++;
        }
        return count;
      }

      expect(hardCount(0.40), greaterThan(hardCount(0.05)));
    });
  });

  group('applyInitialBlockers', () {
    test('hiçbir profil oyunu engelle başlatmaz', () {
      // Başlangıç engelleri kaldırıldı: tahtayı baştan daraltmak yalnızca
      // hayatta kalma süresini kısaltıyordu.
      final generator = PieceGenerator(random: Random(1));
      for (final profile in DifficultyProfiles.all) {
        expect(
          generator.applyInitialBlockers(Board.empty(), profile).filledCount,
          0,
          reason: '${profile.id} engelle başlıyor',
        );
      }
    });

    test('mekanizma duruyor: oran verilirse engel eklenir', () {
      // `applyInitialBlockers` bilerek korundu; ileride "zor mod" istenirse
      // yeniden açılabilsin diye.
      const hard = DifficultyProfile(
        id: 'test',
        label: 'Test',
        minMinutes: 0,
        maxMinutes: null,
        initialBlockerRatio: 0.12,
        hardPieceWeight: 0.3,
        undoCount: 0,
      );
      final generator = PieceGenerator(random: Random(1));
      final board = generator.applyInitialBlockers(Board.empty(), hard);

      expect(board.filledCount, (board.cellCount * 0.12).round());
      expect(board.filledCount, lessThan(board.cellCount ~/ 4));
    });

    test('boş board’da oyun başlangıcında hamle vardır', () {
      final generator = PieceGenerator(random: Random(5));
      final board = generator.applyInitialBlockers(
        Board.empty(),
        DifficultyProfiles.marathon,
      );
      final tray = generator.generateTray(board, DifficultyProfiles.marathon);

      expect(hasAnyLegalMove(board, tray), isTrue);
    });
  });

  group('zorluk yolculuk uzunluğuyla ters orantılı', () {
    test('yolculuk uzadıkça zor parça oranı düşer', () {
      // Regresyon: ilk sürümde tersiydi ve uzun yolculuklarda varış %0'dı.
      expect(
        DifficultyProfiles.marathon.hardPieceWeight,
        lessThan(DifficultyProfiles.standard.hardPieceWeight),
      );
      expect(
        DifficultyProfiles.long.hardPieceWeight,
        lessThan(DifficultyProfiles.standard.hardPieceWeight),
      );
    });

    test('yolculuk uzadıkça geri alma hakkı artar', () {
      expect(
        DifficultyProfiles.marathon.undoCount,
        greaterThan(DifficultyProfiles.standard.undoCount),
      );
      expect(
        DifficultyProfiles.long.undoCount,
        greaterThan(DifficultyProfiles.short.undoCount),
      );
    });
  });
}
