import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';

import '../helpers/metro_fixture.dart';

/// İki renk arasındaki WCAG kontrast oranı.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final metro = MetroFixture.load();

  group('LineTheme.readableOn', () {
    test('her hat rengi için en yüksek kontrastlı metin rengini seçer', () {
      // Regresyon: sabit parlaklık eşiği (>0.42) M3 gibi orta parlaklıktaki
      // renklerde yanlış tarafa düşüyordu.
      for (final line in metro.lines()) {
        for (final background in <Color>[
          line.color,
          LineTheme.from(line.color).accent,
        ]) {
          final chosen = LineTheme.readableOn(background);
          final alternative = chosen == AppColors.background
              ? AppColors.textPrimary
              : AppColors.background;

          expect(
            contrast(chosen, background),
            greaterThanOrEqualTo(contrast(alternative, background)),
            reason: '${line.id}: daha okunur bir alternatif var',
          );
        }
      }
    });

    test('rozet metni grafik nesne eşiğini (3:1) geçer', () {
      // Regresyon: LineBadge metni sabit beyazdı. Ölçüm: M9 1.44:1,
      // M7 2.01:1, M6 2.20:1, M3 2.73:1 — on hattın yedisi okunmuyordu.
      final failures = <String>[];

      for (final line in metro.lines()) {
        final theme = LineTheme.from(line.color);
        for (final entry in <(String, Color, Color)>[
          ('resmi', line.color, theme.onColor),
          ('accent', theme.accent, theme.onAccent),
        ]) {
          final ratio = contrast(entry.$3, entry.$2);
          if (ratio < 3.0) {
            failures.add(
              '${line.id} ${entry.$1}: ${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      }

      expect(failures, isEmpty, reason: 'okunmayan rozetler: $failures');
    });
  });
}
