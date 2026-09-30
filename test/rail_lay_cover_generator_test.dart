@Tags(<String>['tools'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/application/rail_lay_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/data/rail_lay_levels.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/presentation/galata_backdrop.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/presentation/rail_lay_painter.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import 'helpers/metro_fixture.dart';

/// Ray Döşe'nin galeri kapağını üretir — ürün kodu değil, araç.
///
/// Kapak **oyunun kendi çiziminden** çıkıyor: arka planda oyundaki Galata
/// sahnesi ([GalataBackdropPainter]), önünde gerçek bir bölüm, gerçek
/// denetleyiciyle oynatılmış ve [RailLayPainter] ile çizilmiş. Görüntü
/// üretici yok: kartta ne görünüyorsa oyunda da o var.
///
///   flutter test test/rail_lay_cover_generator_test.dart
///   cp build/rail_lay_cover.png assets/images/games/ray_dose_cover.png
///
/// Başlık kapakta yok; galeri onu Bungee ile sol üste yazıyor. Bu yüzden
/// göğün sol üstü sakin bırakıldı, kule sağda.
void main() {
  /// Kart oranı 0,55 (Tünele Kaç kapağıyla aynı ölçü).
  const width = 660.0;
  const height = 1200.0;

  /// Kapaktaki bölüm, çözümün kaçıncı hamlesinde durulacağı ve son kayışta
  /// kaç kare (1/60 sn) ilerleneceği. Son hamle yarıda kesilir: metro
  /// kayarken, arkasında taze döşenmiş ray.
  // Seçim dört aday arasından yapıldı (bölüm 8, 9, 17, 31): 9'da kule
  // tamamen görünüyor, döşenen ray kıvrılıyor ve metro kuleye doğru kayıyor.
  const candidates = <(int, int, int)>[(9, 5, 5)];

  /// M3'ün mavisi: gün batımının turuncusuna karşı en net ayrılan hat rengi.
  const lineColor = Color(0xFF05A8E2);

  for (final (coverLevel, fullMoves, partialFrames) in candidates) {
    test('Ray Döşe kapağı: bölüm $coverLevel', () async {
      final metro = MetroFixture.load();
      final journey = RouteService(
        metro,
      ).estimate('m2_taksim', 'm2_levent').journey!;
      final controller = RailLayController(
        journey: journey,
        recordToBeat: 0,
        startLevel: coverLevel,
      )..start();
      addTearDown(controller.dispose);

      final level = RailLayLevels.byNumber(coverLevel);
      final solution = level.solution;
      for (var i = 0; i < fullMoves && i < solution.length; i++) {
        controller.swipe(solution[i]);
        for (var t = 0; t < 120 && controller.isSliding; t++) {
          controller.debugAdvance(1 / 60);
        }
      }
      if (fullMoves < solution.length) {
        controller.swipe(solution[fullMoves]);
        for (var t = 0; t < partialFrames && controller.isSliding; t++) {
          controller.debugAdvance(1 / 60);
        }
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
      const size = Size(width, height);

      const GalataBackdropPainter().paint(canvas, size);

      // Tahta: alt yarıda, ufkun sıcak ışığının önünde. Hücre tahtayı kart
      // genişliğinin ~%84'üne yayar; kule sağda arkadan yükselir.
      final cell = (width * 0.8) / level.width;
      final board = Size(
        cell * level.width,
        cell * (level.height + railLayBoardDepth),
      );
      final origin = Offset(
        (width - board.width) / 2,
        height - board.height - height * 0.05,
      );
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      RailLayPainter(
        controller: controller,
        lineColor: lineColor,
      ).paint(canvas, board);
      canvas.restore();

      final image = await recorder.endRecording().toImage(
        width.toInt(),
        height.toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File(
        'build/rail_lay_cover.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);

      expect(File('build/rail_lay_cover.png').lengthSync(), greaterThan(1000));
    });
  }
}
