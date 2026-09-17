import 'dart:math' as math;

import 'package:flutter/material.dart' show Color, HSLColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// CIE L* — algısal açıklık. Katman adımlarını ölçmek için.
double lstar(Color c) {
  final y = c.computeLuminance();
  return y > 0.008856 ? 116 * math.pow(y, 1 / 3) - 16 : 903.3 * y;
}

void main() {
  const surfaces = <String, Color>{
    'background': AppColors.background,
    'surface': AppColors.surface,
    'surfaceHigh': AppColors.surfaceHigh,
  };

  group('Nötr skala', () {
    // Regresyon: eski skalada background → boardBackground → surface adımları
    // 3 L* idi. Bu fark gözle seçilemiyor; tahta ve kartlar zeminden
    // ayrışmıyor, arayüz düz bir leke gibi duruyordu.
    test('katmanlar algısal olarak ayrışır (adım ≥ 4 L*)', () {
      const ramp = <String, Color>{
        'background': AppColors.background,
        'boardBackground': AppColors.boardBackground,
        'surface': AppColors.surface,
        'surfaceHigh': AppColors.surfaceHigh,
        'outline': AppColors.outline,
      };
      final entries = ramp.entries.toList();
      for (var i = 1; i < entries.length; i++) {
        final step = lstar(entries[i].value) - lstar(entries[i - 1].value);
        expect(
          step,
          greaterThanOrEqualTo(4.0),
          reason:
              '${entries[i - 1].key} → ${entries[i].key} adımı '
              '${step.toStringAsFixed(1)} L*; gözle seçilemez',
        );
      }
    });

    test('skala tek ton üzerinde kalır', () {
      // Tonun kayması paleti "gri + rastgele mavi" gösterir.
      for (final c in <Color>[
        AppColors.background,
        AppColors.surface,
        AppColors.surfaceHigh,
        AppColors.outline,
        AppColors.textMuted,
        AppColors.textSecondary,
      ]) {
        final hue = HSLColor.fromColor(c).hue;
        expect(
          hue,
          inInclusiveRange(205, 225),
          reason: '$c tonu skalanın dışına çıkmış',
        );
      }
    });
  });

  group('Metin okunurluğu', () {
    // Metro içinde, hareket hâlinde, göz ucuyla okunacak. Küçük etiketler de
    // dahil her metin rengi her yüzeyde WCAG AA'yı geçmeli.
    test('her metin rengi her yüzeyde 4.5:1 geçer', () {
      const texts = <String, Color>{
        'textPrimary': AppColors.textPrimary,
        'textSecondary': AppColors.textSecondary,
        'textMuted': AppColors.textMuted,
      };
      for (final t in texts.entries) {
        for (final s in surfaces.entries) {
          expect(
            contrast(t.value, s.value),
            greaterThanOrEqualTo(4.5),
            reason: '${t.key} / ${s.key}',
          );
        }
      }
    });

    test('birincil buton her zeminde okunur', () {
      expect(
        contrast(AppColors.onAction, AppColors.action),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppColors.action, AppColors.background),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('Oyun glif renkleri', () {
    const glyphColors = <String, Color>{
      'blocks': AppColors.gameBlocks,
      'quiz': AppColors.gameQuiz,
      'merge': AppColors.gameMerge,
      'rail': AppColors.gameRail,
      'drop': AppColors.gameDrop,
      'lanes': AppColors.gameLanes,
    };

    test('hepsi glif kutusunda 3:1 geçer', () {
      for (final entry in glyphColors.entries) {
        expect(
          contrast(entry.value, AppColors.gameGlyphBox),
          greaterThanOrEqualTo(3.0),
          reason: '${entry.key} glif kutusunda ayrışmıyor',
        );
      }
    });

    test('ton açıları birbirine yapışmıyor', () {
      // Önceki set altı pastel tondu ve ikisi ayırt edilemiyordu.
      final hues =
          glyphColors.values.map((c) => HSLColor.fromColor(c).hue).toList()
            ..sort();
      for (var i = 1; i < hues.length; i++) {
        expect(
          hues[i] - hues[i - 1],
          greaterThanOrEqualTo(30.0),
          reason: 'iki oyun rengi çok yakın: ${hues[i - 1]} ve ${hues[i]}',
        );
      }
    });

    test('kilitli oyun rengi açık renklerden ayrışır', () {
      expect(
        contrast(AppColors.gameGlyphLocked, AppColors.gameGlyphBox),
        greaterThanOrEqualTo(3.0),
      );
    });
  });
}
