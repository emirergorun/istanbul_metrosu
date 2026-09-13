import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';

/// İki renk arasındaki WCAG kontrast oranı.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// WCAG'in ince grafik nesne sınırı.
const double kGraphicMinContrast = 3.0;

void main() {
  group('Oyun tahtası okunurluğu', () {
    // Regresyon: ızgara yalnız dolgu farkıyla çiziliyordu ve boş hücre ile
    // tahta zemini arasındaki oran 1.20:1'de kalıyordu — hareket eden
    // metroda tahta düz bir leke gibi görünüyordu.
    test('ızgara çizgisi hem zeminden hem dolgudan 3:1 ayrışır', () {
      expect(
        contrast(AppColors.cellGrid, AppColors.boardBackground),
        greaterThanOrEqualTo(kGraphicMinContrast),
        reason: 'Izgara çizgisi tahta zemininden ayrışmalı',
      );
      expect(
        contrast(AppColors.cellGrid, AppColors.emptyCell),
        greaterThanOrEqualTo(kGraphicMinContrast),
        reason: 'Izgara çizgisi hücre dolgusundan ayrışmalı',
      );
    });

    // Asıl oynanış ayrımı bu: oyuncunun bir karenin dolu mu boş mu olduğunu
    // göz ucuyla görmesi gerekiyor.
    test('her blok rengi boş hücreden 3:1 ayrışır', () {
      for (final block in AppColors.blocks) {
        expect(
          contrast(block, AppColors.emptyCell),
          greaterThanOrEqualTo(kGraphicMinContrast),
          reason: 'Blok rengi $block boş hücreden ayrışmalı',
        );
      }
    });

    // Engel hücresi renk olarak boş hücreye yakın (1.78:1); bu bilinçli,
    // çünkü onu 3:1'e çıkarmak ızgara çizgisiyle karıştırırdı. Ayrım
    // `_paintBlockerHatch` taraması ile kuruluyor — yani renk tek başına
    // bilgi taşımıyor. Bu test o dengeyi sabitler: engel, boş hücreden
    // *biraz* ayrışmalı ama bloklar kadar değil.
    test('engel hücresi boş hücreden ayrışır ama bloklarla karışmaz', () {
      final vsEmpty = contrast(AppColors.blocker, AppColors.emptyCell);
      expect(vsEmpty, greaterThan(1.3));
      for (final block in AppColors.blocks) {
        expect(
          contrast(AppColors.blocker, block),
          greaterThan(1.5),
          reason: 'Engel, blok rengi $block ile karışmamalı',
        );
      }
    });
  });
}
